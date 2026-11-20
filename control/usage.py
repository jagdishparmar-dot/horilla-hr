"""Usage snapshots. The tenant list never calls this module."""

from pathlib import Path

from django.conf import settings
from django.db import transaction
from django.utils import timezone

from control.context import activate_tenant_alias, clear_tenant_alias
from control.crypto import redact_job_error
from control.db import ensure_tenant_connection

# A past-due tenant is still served and still billed, so it is still measured.
SNAPSHOT_STATUSES = ("active", "trialing", "past_due")
_GB = 1024 ** 3


def count_employees(alias: str) -> int:
    """Billable headcount: employee records that are not archived.

    ``Employee.is_active`` is the archive flag. Offboarding, the single archive
    and the bulk archive all clear it, and un-archiving sets it again. The count
    covers every company in the tenant, so it reads the base manager rather than
    the company-scoped one. Administrators count like anyone else, and an
    employee with login access switched off is still on the payroll.
    """
    from employee.models import Employee

    return Employee._base_manager.using(alias).filter(is_active=True).count()


def count_archived_employees(alias: str) -> int:
    from employee.models import Employee

    return Employee._base_manager.using(alias).filter(is_active=False).count()


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
    """Count employees and media for one tenant, then clear the alias.

    Both counts are read before anything is written, so a failed read leaves
    the tenant and its history untouched. Today's history row keeps the day's
    highest reading, which is the figure billing uses.
    """
    alias = connect(tenant)
    token = activate_tenant_alias(alias)
    try:
        seats = count_employees(alias)
        archived = count_archived_employees(alias)
        used = measure_storage_gb(tenant.slug)
    finally:
        clear_tenant_alias(token)
    now = timezone.now()
    with transaction.atomic():
        tenant.active_seats = seats
        tenant.used_storage_gb = used
        tenant.usage_updated_at = now
        tenant.save(update_fields=["active_seats", "used_storage_gb", "usage_updated_at"])
        record_usage_day(tenant, seats, archived, day=timezone.localdate(now))


def record_usage_day(tenant, active, archived, *, day) -> None:
    from control.models import TenantUsageDay

    row, created = TenantUsageDay.objects.select_for_update().get_or_create(
        tenant=tenant,
        day=day,
        defaults={"active_employees": active, "archived_employees": archived},
    )
    if created:
        return
    row.active_employees = max(row.active_employees, active)
    row.archived_employees = archived
    row.save(update_fields=["active_employees", "archived_employees", "recorded_at"])


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
