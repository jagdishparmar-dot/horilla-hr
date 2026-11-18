"""pg_dump and pg_restore for one tenant database.

The control database is never the dump target. Dump files live in
``backups/<slug>/`` and are not world-readable.
"""

import os
import stat
import subprocess
from datetime import datetime
from pathlib import Path

from django.conf import settings
from django.utils import timezone

from control.crypto import redact_job_error


def backup_dir(slug: str) -> Path:
    return Path(settings.BASE_DIR) / "backups" / slug


def dump_path(slug: str, when: datetime | None = None) -> Path:
    moment = when or timezone.now()
    stamp = moment.strftime("%Y%m%dT%H%M%S%fZ")
    return backup_dir(slug) / f"{stamp}.dump"


def resolve_dump(slug: str, dump_name: str) -> Path:
    """A dump file in this tenant's folder. A name from another folder is refused."""
    from control.provisioning import ProvisionError

    if not dump_name or dump_name != Path(dump_name).name:
        raise ProvisionError("Dump name is not valid.")
    root = backup_dir(slug).resolve()
    target = (root / dump_name).resolve()
    if target.parent != root:
        raise ProvisionError("Dump is not in this tenant's backup folder.")
    return target


def _pg_env(password: str) -> dict:
    env = os.environ.copy()
    env["PGPASSWORD"] = password
    return env


def _chmod_private(path: Path) -> None:
    path.chmod(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP)


def _stderr_text(stderr) -> str:
    if stderr is None:
        return ""
    if isinstance(stderr, bytes):
        return stderr.decode("utf-8", errors="replace")
    return str(stderr)


def _stderr_tail(stderr) -> str:
    for line in reversed(_stderr_text(stderr).splitlines()):
        text = line.strip()
        if text:
            return text
    return ""


def _scrub_password(text: str, password: str) -> str:
    if not text or not password:
        return text
    return text.replace(password, "[redacted]")


def _run_pg(command, password: str, *, timed_out: str, failed: str) -> None:
    from control.provisioning import ProvisionError

    try:
        subprocess.run(
            command,
            check=True,
            env=_pg_env(password),
            capture_output=True,
            text=True,
            timeout=1800,
        )
    except subprocess.TimeoutExpired as exc:
        raise ProvisionError(timed_out) from exc
    except subprocess.CalledProcessError as exc:
        tail = _scrub_password(_stderr_tail(exc.stderr), password)
        if isinstance(exc.stderr, str) and password:
            exc.stderr = _scrub_password(exc.stderr, password)
        if not tail:
            raise ProvisionError(f"{failed}.") from exc
        raise ProvisionError(f"{failed}: {redact_job_error(tail)}") from exc


def dump_tenant_database(tenant, when: datetime | None = None) -> str:
    from control.provisioning import ProvisionError

    binary = _require_binary("pg_dump")
    path = dump_path(tenant.slug, when)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)
    command = [
        binary,
        "-h",
        tenant.db_host or "db",
        "-p",
        str(tenant.db_port or 5432),
        "-U",
        tenant.db_user,
        "-F",
        "c",
        "-f",
        str(path),
        tenant.db_name,
    ]
    if tenant.db_name == settings.DATABASES["default"]["NAME"]:
        raise ProvisionError("Refusing to dump the control database as a tenant.")
    _run_pg(
        command,
        tenant.db_password(),
        timed_out="Tenant dump timed out.",
        failed="Tenant dump failed",
    )
    _chmod_private(path)
    return str(path)


def restore_tenant_database(tenant, dump_name: str) -> None:
    from control.provisioning import ProvisionError

    binary = _require_binary("pg_restore")
    target = resolve_dump(tenant.slug, dump_name)
    if not target.is_file():
        raise ProvisionError("Dump file was not found.")
    # The folder name is the only slug this restore may touch.
    if target.parent.name != tenant.slug:
        raise ProvisionError("Dump is not in this tenant's backup folder.")
    command = [
        binary,
        "-h",
        tenant.db_host or "db",
        "-p",
        str(tenant.db_port or 5432),
        "-U",
        tenant.db_user,
        "-d",
        tenant.db_name,
        "--clean",
        "--if-exists",
        "--no-owner",
        str(target),
    ]
    if tenant.db_name == settings.DATABASES["default"]["NAME"]:
        raise ProvisionError("Refusing to restore into the control database.")
    _run_pg(
        command,
        tenant.db_password(),
        timed_out="Tenant restore timed out.",
        failed="Tenant restore failed",
    )


def _require_binary(name: str) -> str:
    import shutil

    from control.provisioning import ProvisionError

    binary = shutil.which(name)
    if not binary:
        raise ProvisionError(f"{name} is not installed.")
    return binary
