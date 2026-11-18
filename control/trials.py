"""Close lapsed trials. Past-due stays routable. No invoice is issued."""

from django.db import transaction
from django.utils import timezone

from control.models import Tenant


def expire_trials(now=None) -> int:
    """Set trialing tenants whose trial_ends_at has passed to past_due.

    Leaves trial_ends_at in place so an operator can still convert them.
    Does not issue an invoice and does not suspend. Returns how many rows changed.
    """
    moment = now or timezone.now()
    changed = 0
    stale_ids = list(
        Tenant.objects.filter(
            status=Tenant.Status.TRIALING,
            trial_ends_at__isnull=False,
            trial_ends_at__lte=moment,
        ).values_list("pk", flat=True)
    )
    for tenant_id in stale_ids:
        with transaction.atomic():
            locked = (
                Tenant.objects.select_for_update()
                .filter(
                    pk=tenant_id,
                    status=Tenant.Status.TRIALING,
                    trial_ends_at__isnull=False,
                    trial_ends_at__lte=moment,
                )
                .first()
            )
            if locked is None:
                continue
            locked.status = Tenant.Status.PAST_DUE
            locked.save(update_fields=["status"])
            changed += 1
    return changed
