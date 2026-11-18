"""Usage snapshots. The tenant list never calls this module."""

from pathlib import Path

from django.conf import settings
from django.utils import timezone

from control.context import activate_tenant_alias, clear_tenant_alias
from control.crypto import redact_job_error
from control.db import ensure_tenant_connection

SNAPSHOT_STATUSES = ("active", "trialing")
_GB = 1024 ** 3


def count_employees(alias: str) -> int:
    from employee.models import Employee

    return Employee._base_manager.using(alias).count()


def measure_storage_gb(slug: str) -> int:
    root = Path(settings.MEDIA_ROOT) / slug
    if not root.is_dir():
        return 0
    total = 0
    for path in root.rglob("*"):
        if path.is_file() and not path.is_symlink():
            total += path.stat().st_size
    return total // _GB


def snapshot_tenant(tenant, *, connect=ensure_tenant_connection) -> None:
    """Count employees and media for one tenant, then clear the alias."""
    alias = connect(tenant)
    token = activate_tenant_alias(alias)
    try:
        seats = count_employees(alias)
        used = measure_storage_gb(tenant.slug)
    finally:
        clear_tenant_alias(token)
    tenant.active_seats = seats
    tenant.used_storage_gb = used
    tenant.usage_updated_at = timezone.now()
    tenant.save(update_fields=["active_seats", "used_storage_gb", "usage_updated_at"])


def snapshot_usage(slug=None, *, connect=ensure_tenant_connection) -> list[str]:
    """Snapshot one slug, or every active and trialing tenant.

    A failure is recorded and the loop continues. The tenant that failed is
    left unchanged because the write happens only after a successful read.
    """
    from control.models import Tenant

    if slug:
        tenants = list(Tenant.objects.filter(slug=slug))
    else:
        tenants = list(
            Tenant.objects.filter(status__in=SNAPSHOT_STATUSES).order_by("slug")
        )
    errors = []
    for tenant in tenants:
        try:
            snapshot_tenant(tenant, connect=connect)
        except Exception as exc:
            errors.append(f"{tenant.slug}: {redact_job_error(str(exc))}")
    return errors
