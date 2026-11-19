"""pg_dump and pg_restore for one tenant database.

The control database is never the dump target. The local ``backups/<slug>/``
folder is the spool: when the S3-compatible store is configured
(``BACKUP_S3_BUCKET``), a finished dump is uploaded there and the spool file
is removed; otherwise the local folder is the system of record and must be a
named volume in production. Dump files are not world-readable.
"""

import os
import re
import stat
import subprocess
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

from django.conf import settings
from django.utils import timezone

from control import backup_store
from control.backup_store import BackupStoreError
from control.crypto import redact_job_error

# Names written by dump_path(). Retention only ever deletes names that match,
# so a hand-placed dump (sample.dump, pre-cutover copies) is never pruned.
TIMESTAMP_NAME_RE = re.compile(r"^\d{8}T\d{12}Z\.dump$")

# Dumps of a deleted tenant are kept this long after deleted_at, then removed.
DELETED_DUMP_RETENTION = timedelta(days=30)


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
    """Dump one tenant. Returns the object key, or the local path in fallback mode.

    With the store configured the spool file is uploaded and removed; an
    upload failure fails the job (and, through the delete flow's fail-closed
    rule, keeps the database from being dropped). The spool file is kept on
    upload failure so an operator can still salvage it by hand.
    """
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
    if backup_store.configured():
        try:
            stored = backup_store.put(path, tenant.slug, path.name)
        except BackupStoreError as exc:
            raise ProvisionError(f"Tenant dump upload failed: {exc}") from exc
        path.unlink()
        return stored["key"]
    return str(path)


def restore_tenant_database(tenant, dump_name: str) -> None:
    from control.provisioning import ProvisionError

    binary = _require_binary("pg_restore")
    if tenant.db_name == settings.DATABASES["default"]["NAME"]:
        raise ProvisionError("Refusing to restore into the control database.")
    if backup_store.configured():
        try:
            backup_store.validate_dump_name(dump_name)
            stored = backup_store.head(tenant.slug, dump_name)
        except BackupStoreError as exc:
            raise ProvisionError(str(exc)) from exc
        if stored is not None:
            _restore_from_store(binary, tenant, dump_name)
            return
        # Not in the store: fall through to a pre-store local dump, if any.
    target = resolve_dump(tenant.slug, dump_name)
    if not target.is_file():
        raise ProvisionError("Dump file was not found.")
    # The folder name is the only slug this restore may touch.
    if target.parent.name != tenant.slug:
        raise ProvisionError("Dump is not in this tenant's backup folder.")
    _run_restore_command(binary, tenant, target)


def _restore_from_store(binary: str, tenant, dump_name: str) -> None:
    """Download to a private spool file, restore, and always remove the file."""
    from control.provisioning import ProvisionError

    folder = backup_dir(tenant.slug)
    folder.mkdir(parents=True, exist_ok=True)
    folder.chmod(stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP)
    handle, raw = tempfile.mkstemp(prefix=".restore-", suffix=".dump", dir=folder)
    os.close(handle)
    spool = Path(raw)
    try:
        try:
            backup_store.get(tenant.slug, dump_name, spool)
        except BackupStoreError as exc:
            raise ProvisionError(str(exc)) from exc
        _run_restore_command(binary, tenant, spool)
    finally:
        spool.unlink(missing_ok=True)


def _run_restore_command(binary: str, tenant, dump_file: Path) -> None:
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
        str(dump_file),
    ]
    _run_pg(
        command,
        tenant.db_password(),
        timed_out="Tenant restore timed out.",
        failed="Tenant restore failed",
    )


def list_dumps(slug: str) -> list[dict]:
    """This tenant's dumps, newest first: ``{"name", "size", "last_modified"}``.

    Reads the store when configured, else the local folder. Spool temp files
    (names starting with a dot) are never listed.
    """
    if backup_store.configured():
        return backup_store.list_keys(slug)
    folder = backup_dir(slug)
    if not folder.is_dir():
        return []
    entries = []
    for path in folder.iterdir():
        name = path.name
        if not path.is_file() or name.startswith(".") or not name.endswith(".dump"):
            continue
        info = path.stat()
        entries.append(
            {
                "name": name,
                "size": info.st_size,
                "last_modified": datetime.fromtimestamp(
                    info.st_mtime, tz=timezone.get_current_timezone()
                ),
            }
        )
    entries.sort(key=lambda entry: entry["name"], reverse=True)
    return entries


def _parse_stamp(name: str) -> datetime:
    return datetime.strptime(name[: -len(".dump")], "%Y%m%dT%H%M%S%fZ")


def retention_victims(names, keep_daily: int, keep_weekly: int) -> list[str]:
    """Names to delete. Keeps the newest ``keep_daily`` dumps, then the newest
    dump of each of the next ``keep_weekly`` distinct ISO weeks. Names that do
    not match the timestamp pattern are never victims."""
    dated = sorted(
        (name for name in names if TIMESTAMP_NAME_RE.fullmatch(name)),
        key=_parse_stamp,
        reverse=True,
    )
    keep = set(dated[:keep_daily])
    weeks_kept = []
    for name in dated[keep_daily:]:
        week = _parse_stamp(name).isocalendar()[:2]
        if week not in weeks_kept and len(weeks_kept) < keep_weekly:
            weeks_kept.append(week)
            keep.add(name)
    return [name for name in dated if name not in keep]


def prune_backups(slug: str) -> list[str]:
    """Apply the retention policy to one tenant. Returns the deleted names."""
    keep_daily = backup_store.keep_daily()
    keep_weekly = backup_store.keep_weekly()
    names = [entry["name"] for entry in list_dumps(slug)]
    victims = retention_victims(names, keep_daily, keep_weekly)
    for name in victims:
        _delete_dump(slug, name)
    return victims


def _delete_dump(slug: str, name: str) -> None:
    if backup_store.configured():
        backup_store.delete(slug, name)
        return
    target = backup_dir(slug) / name
    if target.is_file():
        target.unlink()


def prune_deleted_tenant_dumps(now=None) -> int:
    """Remove every dump of tenants deleted more than 30 days ago.

    Returns how many dump files or objects were removed. One tenant's store
    error does not stop the sweep for the others.
    """
    from control.models import Tenant

    moment = now or timezone.now()
    cutoff = moment - DELETED_DUMP_RETENTION
    removed = 0
    slugs = Tenant.objects.filter(
        status=Tenant.Status.DELETED,
        deleted_at__isnull=False,
        deleted_at__lte=cutoff,
    ).values_list("slug", flat=True)
    for slug in slugs:
        try:
            for entry in list_dumps(slug):
                _delete_dump(slug, entry["name"])
                removed += 1
        except BackupStoreError:
            continue
    return removed


def _require_binary(name: str) -> str:
    import shutil

    from control.provisioning import ProvisionError

    binary = shutil.which(name)
    if not binary:
        raise ProvisionError(f"{name} is not installed.")
    return binary
