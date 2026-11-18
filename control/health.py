"""Three checks for one tenant. Details never include a password or a connection string."""

from dataclasses import dataclass
from datetime import timedelta
from pathlib import Path

from django.db import connections
from django.utils import timezone

from control.backup import backup_dir
from control.models import ProvisionJob, Tenant

BACKUP_STALE_AFTER = timedelta(days=7)
STORAGE_DEGRADED_PERCENT = 85


@dataclass(frozen=True)
class HealthLine:
    name: str
    status: str
    detail: str


def tenant_health(tenant, now=None) -> list[HealthLine]:
    moment = now or timezone.now()
    return [
        _connection_line(tenant),
        _backup_line(tenant, moment),
        _migrate_line(tenant),
        _storage_line(tenant),
    ]


def _line(name, status, detail) -> HealthLine:
    return HealthLine(name=name, status=status, detail=detail)


def _connection_line(tenant) -> HealthLine:
    try:
        _probe_connection(tenant)
    except Exception:
        return _line("connection", "failed", "Could not open the tenant database.")
    return _line("connection", "healthy", "Tenant role opened the database.")


def _probe_connection(tenant) -> None:
    from control.db import ensure_tenant_connection

    alias = ensure_tenant_connection(tenant)
    try:
        with connections[alias].cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
    finally:
        if alias in connections:
            connections[alias].close()


def _backup_line(tenant, now) -> HealthLine:
    newest = (
        tenant.jobs.filter(
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
        )
        .order_by("-finished_at", "-pk")
        .first()
    )
    if newest is None:
        return _line("backup", "failed", "No successful backup.")
    if not _dump_file_present(tenant, newest):
        return _line("backup", "failed", "Dump file is missing.")
    finished = newest.finished_at
    if finished is None or finished < now - BACKUP_STALE_AFTER:
        return _line("backup", "degraded", "Newest backup is older than 7 days.")
    return _line("backup", "healthy", "Newest backup is present.")


def _dump_file_present(tenant, job) -> bool:
    raw = str((job.payload or {}).get("dump_path") or "")
    if not raw:
        return False
    root = backup_dir(tenant.slug).resolve()
    try:
        path = Path(raw).resolve()
    except OSError:
        return False
    return path.parent == root and path.is_file()


def _migrate_line(tenant) -> HealthLine:
    """Control-database jobs only. Do not open the tenant database."""
    migrates = tenant.jobs.filter(kind=ProvisionJob.Kind.MIGRATE)
    newest = migrates.order_by("-pk").first()
    if newest is not None and newest.status == ProvisionJob.Status.SUCCEEDED:
        return _line("migrate", "healthy", "Newest migrate succeeded.")
    if migrates.filter(status=ProvisionJob.Status.FAILED).exists():
        return _line("migrate", "failed", "Migrate has not succeeded.")
    if tenant.status == Tenant.Status.ACTIVE:
        return _line("migrate", "healthy", "Active and no failed migrate.")
    if tenant.status in (Tenant.Status.TRIALING, Tenant.Status.PAST_DUE):
        return _line("migrate", "healthy", "No failed migrate.")
    created = tenant.jobs.filter(
        kind=ProvisionJob.Kind.CREATE,
        status=ProvisionJob.Status.SUCCEEDED,
    ).exists()
    if created:
        return _line("migrate", "healthy", "Create succeeded.")
    return _line("migrate", "failed", "Migrate has not succeeded.")


def _storage_line(tenant) -> HealthLine:
    limit = tenant.storage_limit_gb or 0
    used = tenant.used_storage_gb or 0
    if limit and used * 100 >= limit * STORAGE_DEGRADED_PERCENT:
        return _line("storage", "degraded", "Snapshot is at least 85% of the storage limit.")
    return _line("storage", "healthy", "Snapshot is under 85% of the storage limit.")
