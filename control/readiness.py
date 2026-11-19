"""Control-database facts for the readiness probe. No tenant connection."""

from django.db.models import Max

from control.models import ProvisionJob


def tenant_migration_status() -> str:
    """``failed:<slug>`` only when that tenant's newest migrate job failed."""
    try:
        newest = (
            ProvisionJob.objects.filter(kind=ProvisionJob.Kind.MIGRATE)
            .values("tenant_id")
            .annotate(latest=Max("pk"))
            .values_list("latest", flat=True)
        )
        job = (
            ProvisionJob.objects.filter(
                pk__in=newest,
                status=ProvisionJob.Status.FAILED,
            )
            .select_related("tenant")
            .order_by("-pk")
            .first()
        )
    except Exception:
        return "error"
    if job is None:
        return "ok"
    return f"failed:{job.tenant.slug}"
