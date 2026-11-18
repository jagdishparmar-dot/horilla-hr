"""Seat quotes in whole Indian rupees. Nothing here charges a customer.

One function prices a plan, its add-ons, and the selected billing cycle.
Stored cycle prices win. When a cycle row is missing, the monthly unit is
expanded with ``cycle_amounts`` so the locked annual discount still holds.
"""

from dataclasses import dataclass

from control.catalog import CYCLE_MONTHS, cycle_amounts
from control.models import Addon, AddonPrice, Plan, PlanPrice, Tenant


@dataclass(frozen=True)
class Quote:
    base_monthly: int
    discount: int
    addon_monthly: int
    total_monthly: int
    annual: int
    term: int = 0
    setup_fee: int = 0


def _plan(plan) -> Plan:
    if isinstance(plan, Plan):
        return plan
    return Plan.objects.get(code=plan)


def _addon_rows(addon_ids):
    codes = [code for code in (addon_ids or []) if code]
    if not codes:
        return []
    return list(Addon.objects.filter(code__in=codes))


def _stored_plan_unit(plan, cadence):
    if not plan.pk:
        return None
    row = PlanPrice.objects.filter(plan=plan, cadence=cadence).only("unit_rupees").first()
    return None if row is None else int(row.unit_rupees)


def _stored_addon_unit(addon, cadence):
    if not addon.pk:
        return None
    row = AddonPrice.objects.filter(addon=addon, cadence=cadence).only("unit_rupees").first()
    return None if row is None else int(row.unit_rupees)


def catalog_plan_unit(plan, cadence) -> int:
    chosen = _plan(plan)
    stored = _stored_plan_unit(chosen, cadence)
    if stored is not None:
        return stored
    return cycle_amounts(chosen.monthly_price).get(cadence, int(chosen.monthly_price))


def catalog_addon_unit(addon, cadence) -> int:
    stored = _stored_addon_unit(addon, cadence)
    if stored is not None:
        return stored
    return cycle_amounts(addon.amount).get(cadence, int(addon.amount))


def addon_fits(addon, plan) -> bool:
    """Active add-ons with no compatible plans fit every plan."""
    if not addon.is_active:
        return False
    if not addon.compatible_plans.exists():
        return True
    return addon.compatible_plans.filter(pk=plan.pk).exists()


def required_addon_codes(plan) -> list[str]:
    codes = []
    for addon in Addon.objects.filter(is_active=True, required=True):
        if addon_fits(addon, plan):
            codes.append(addon.code)
    return codes


def quote(
    plan,
    cadence,
    seats,
    addon_ids,
    locked_plan_unit=None,
    locked_addon_units=None,
) -> Quote:
    """Price one subscription.

    ``base_monthly`` is the seat total before a cycle discount.
    ``term`` is the amount due for the selected billing cycle.
    ``annual`` is twelve times the monthly equivalent, which matches the
    annual bill when the cycle is annual and the term divides evenly.
    """
    chosen = _plan(plan)
    if cadence not in CYCLE_MONTHS:
        cadence = Tenant.Cadence.MONTHLY
    months = CYCLE_MONTHS[cadence]
    seat_count = max(0, int(seats or 0))
    gross_seats = seat_count * int(chosen.monthly_price)
    rows = _addon_rows(addon_ids)
    gross_addons = 0
    for addon in rows:
        gross_addons += addon.amount * seat_count if addon.per_seat else addon.amount
    plan_unit = (
        int(locked_plan_unit)
        if locked_plan_unit is not None
        else catalog_plan_unit(chosen, cadence)
    )
    locks = locked_addon_units or {}
    seat_term = seat_count * plan_unit
    addon_term = 0
    for addon in rows:
        locked = locks.get(addon.code)
        unit = int(locked) if locked is not None else catalog_addon_unit(addon, cadence)
        addon_term += unit * seat_count if addon.per_seat else unit
    term = seat_term + addon_term
    total_monthly = term // months
    addon_monthly = addon_term // months
    discount = (gross_seats + gross_addons) - total_monthly
    return Quote(
        base_monthly=gross_seats,
        discount=discount,
        addon_monthly=addon_monthly,
        total_monthly=total_monthly,
        annual=total_monthly * 12,
        term=term,
        setup_fee=int(chosen.setup_fee_rupees or 0),
    )


def quote_tenant(tenant) -> Quote:
    """Price the tenant from its locked units, or the catalog when unset."""
    if tenant.plan_fk_id is None:
        return Quote(0, 0, 0, 0, 0, 0, 0)
    links = list(tenant.subscription_addons.select_related("addon"))
    codes = [link.addon.code for link in links]
    locks = {
        link.addon.code: link.locked_unit
        for link in links
        if link.locked_unit is not None
    }
    return quote(
        tenant.plan_fk,
        tenant.cadence,
        tenant.seat_limit,
        codes,
        locked_plan_unit=tenant.locked_plan_unit,
        locked_addon_units=locks,
    )


def lock_subscription(tenant) -> None:
    """Copy the current catalog units onto the tenant. Later catalog edits stay off it."""
    if tenant.plan_fk_id is None:
        tenant.locked_plan_unit = None
        tenant.save(update_fields=["locked_plan_unit"])
        return
    tenant.locked_plan_unit = catalog_plan_unit(tenant.plan_fk, tenant.cadence)
    tenant.save(update_fields=["locked_plan_unit"])
    for link in tenant.subscription_addons.select_related("addon"):
        link.locked_unit = catalog_addon_unit(link.addon, tenant.cadence)
        link.save(update_fields=["locked_unit"])
