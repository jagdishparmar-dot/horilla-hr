"""
pg_backup.scheduler

This module sets up scheduled PostgreSQL backups using APScheduler and pg_dump.

Backups are only enabled if the configured Django database engine is PostgreSQL.
It supports backing up the default Django database at multiple daily times,
configured via environment variables.

Environment Variables:
----------------------
- BACKUP_CRON_TIMES (str, optional)
    A comma-separated list of times in 24h format ("HH:MM") to run backups.
    Example: "02:00,10:00,18:00"
    Default: "02:00,10:00,18:00"
    If unset or empty, scheduling is disabled and no automated backups will run.

- BACKUP_DIR (str, optional)
    Directory path where PostgreSQL backups will be stored.
    Default: <project_root>/pg_backup/backups

Requirements:
-------------
- The system must have `pg_dump` available in PATH.
- The database user must have permission to perform backups.
- APScheduler and django-environ must be installed and configured.

Logging:
--------
Logs are emitted using the `pg_backup` logger and include backup progress and scheduler setup.
Logging format and handlers can be customized via `LOGGING_CONFIG` in this module.

Usage:
------
This module is automatically executed when imported (e.g., from Django AppConfig's `ready()`).
Backups can also be triggered manually by calling `backup_postgres()`.

"""

import datetime
import logging
import logging.config
import os
import shutil
import subprocess
from pathlib import Path

import environ
from django.conf import settings

# === Logging Configuration ===

LOGGING_CONFIG = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "standard": {"format": "[%(asctime)s] [%(levelname)s] %(name)s: %(message)s"},
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "standard",
        },
    },
    "loggers": {
        "pg_backup": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}

logging.config.dictConfig(LOGGING_CONFIG)
logger = logging.getLogger("pg_backup")

# === Configuration ===

env = environ.Env()

default_backup_dir = Path(settings.BASE_DIR) / "pg_backup" / "backups"
BACKUP_DIR = Path(env("BACKUP_DIR", default=str(default_backup_dir)))
BACKUP_CRON_TIMES = env("BACKUP_CRON_TIMES", default="02:00,10:00,18:00")
DATE_FORMAT = "%Y-%m-%d_%H-%M-%S"

# Load DB settings
db = settings.DATABASES["default"]
DB_ENGINE = db["ENGINE"]

DB_NAME = db["NAME"]
DB_USER = db["USER"]
DB_PASSWORD = db["PASSWORD"]
DB_HOST = db.get("HOST", "localhost")
DB_PORT = str(db.get("PORT", 5432))


def backup_default_database():
    """Dump the single database. Multi-tenant mode does not use this path."""
    timestamp = datetime.datetime.now().strftime(DATE_FORMAT)
    backup_file = BACKUP_DIR / f"{DB_NAME}_backup_{timestamp}.sql"
    os.makedirs(BACKUP_DIR, exist_ok=True)
    env = os.environ.copy()
    env["PGPASSWORD"] = DB_PASSWORD
    command = [
        shutil.which("pg_dump") or "pg_dump",
        "-h",
        DB_HOST,
        "-p",
        DB_PORT,
        "-U",
        DB_USER,
        "-F",
        "c",
        "-b",
        "-f",
        str(backup_file),
        DB_NAME,
    ]
    try:
        logger.info("Starting backup: %s", backup_file)
        subprocess.run(command, check=True, env=env)
        logger.info("Backup successful: %s", backup_file)
    except subprocess.CalledProcessError as e:
        logger.error("Backup failed: %s", e)
        raise
    finally:
        env.pop("PGPASSWORD", None)


def backup_postgres():
    """Nightly entry point. One job per active tenant, or the single database."""
    from django.conf import settings as django_settings

    if getattr(django_settings, "HORILLA_MULTITENANT", False):
        from control.models import Tenant
        from control.provisioning import enqueue_backup

        for tenant in Tenant.objects.filter(status=Tenant.Status.ACTIVE).order_by("pk"):
            enqueue_backup(tenant)
        return
    if "postgresql" not in DB_ENGINE:
        logger.warning("Skipping backup: not a PostgreSQL database.")
        return
    backup_default_database()


def _register_backup_times():
    from horilla.scheduling import register_job

    if not BACKUP_CRON_TIMES:
        logger.warning("BACKUP_CRON_TIMES not set. Scheduler is disabled.")
        return
    for time_str in [t.strip() for t in BACKUP_CRON_TIMES.split(",") if t.strip()]:
        try:
            hour, minute = map(int, time_str.split(":"))
        except ValueError:
            logger.error("Invalid time format in BACKUP_CRON_TIMES: '%s'", time_str)
            continue
        register_job(
            backup_postgres,
            "cron",
            job_id=f"pg_backup.backup_postgres.{hour:02d}{minute:02d}",
            hour=hour,
            minute=minute,
            per_tenant=False,
        )
        logger.info("Backup scheduled at %02d:%02d", hour, minute)


_register_backup_times()
