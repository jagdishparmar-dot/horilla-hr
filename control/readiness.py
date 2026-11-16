"""Control-database facts for the readiness probe. No tenant connection."""

from control.models import ProvisionJob


def tenant_migration_status() -> str:
    try:
        job = (
            ProvisionJob.objects.filter(
                kind=ProvisionJob.Kind.MIGRATE,
                status=ProvisionJob.Status.FAILED,
            )
            .select_related("tenant")
            .order_by("-finished_at", "-pk")
            .first()
        )
    except Exception:
        return "error"
    if job is None:
        return "ok"
    return f"failed:{job.tenant.slug}"
