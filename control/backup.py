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
    try:
        subprocess.run(
            command,
            check=True,
            env=_pg_env(tenant.db_password()),
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ProvisionError("Tenant dump failed.") from exc
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
    try:
        subprocess.run(
            command,
            check=True,
            env=_pg_env(tenant.db_password()),
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        raise ProvisionError("Tenant restore failed.") from exc


def _require_binary(name: str) -> str:
    import shutil

    from control.provisioning import ProvisionError

    binary = shutil.which(name)
    if not binary:
        raise ProvisionError(f"{name} is not installed.")
    return binary
