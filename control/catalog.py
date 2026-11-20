"""INR plan catalog. Prices are whole rupees, exclusive of GST.

The India list is the PeopleLedger USD amount multiplied by 100.
Starter is ₹800 because the prototype seat price is 8. This is the locked
seed, not a daily exchange rate.
"""

UNASSIGNED = "unassigned"
SELLABLE_CODES = ("starter", "growth", "enterprise")
ANNUAL_DISCOUNT_PERCENT = 20
CYCLE_MONTHS = {"monthly": 1, "semiannual": 6, "annual": 12}


def cycle_amounts(monthly: int) -> dict:
    """Term price for each cycle from a monthly unit.

    Monthly is the unit itself. Semi-annual is six months with no extra
    discount. Annual is twelve months with the locked 20% discount, using
    the same half-up rounding as ``quote``.
    """
    monthly = int(monthly or 0)
    annual = (monthly * 12 * (100 - ANNUAL_DISCOUNT_PERCENT) + 50) // 100
    return {
        "monthly": monthly,
        "semiannual": monthly * 6,
        "annual": annual,
    }

PLANS = (
    {
        "code": "starter",
        "name": "Starter",
        "monthly_price": 800,
        "seat_cap": 100,
        "is_active": True,
        "sort_order": 1,
    },
    {
        "code": "growth",
        "name": "Growth",
        "monthly_price": 1400,
        "seat_cap": 1000,
        "is_active": True,
        "sort_order": 2,
    },
    {
        "code": "enterprise",
        "name": "Enterprise",
        "monthly_price": 2200,
        "seat_cap": None,
        "is_active": True,
        "sort_order": 3,
    },
    {
        "code": UNASSIGNED,
        "name": "Unassigned",
        "monthly_price": 0,
        "seat_cap": None,
        "is_active": True,
        "sort_order": 9,
    },
)

ADDONS = (
    {
        "code": "multi_state_tax",
        "name": "Multi-State Payroll Tax Filing",
        "amount": 18000,
        "per_seat": False,
    },
    {
        "code": "calibration_360",
        "name": "360° Calibration & Succession",
        "amount": 300,
        "per_seat": True,
    },
    {
        "code": "audit_vault",
        "name": "Dedicated Compliance Vault",
        "amount": 14000,
        "per_seat": False,
    },
    {
        "code": "priority_sla",
        "name": "Priority SLA",
        "amount": 26000,
        "per_seat": False,
    },
)


def plan_code_for_label(label) -> str:
    code = (label or "").strip().lower()
    if code in SELLABLE_CODES:
        return code
    return UNASSIGNED


def format_inr(amount) -> str:
    value = int(amount or 0)
    sign = "-" if value < 0 else ""
    digits = str(abs(value))
    if len(digits) <= 3:
        grouped = digits
    else:
        head, tail = digits[:-3], digits[-3:]
        parts = []
        while head:
            parts.append(head[-2:])
            head = head[:-2]
        grouped = ",".join(reversed(parts)) + "," + tail
    return f"{sign}₹{grouped}"


def sellable_plans():
    """Active plans an operator can assign. Unassigned stays off the list."""
    from control.models import Plan

    return Plan.objects.filter(is_active=True).exclude(code=UNASSIGNED).order_by(
        "sort_order", "code"
    )


def seed_catalog(apps, schema_editor=None):
    """Insert the locked catalog. A second call updates rows and does not duplicate them."""
    Plan = apps.get_model("control", "Plan")
    Addon = apps.get_model("control", "Addon")
    for row in PLANS:
        Plan.objects.update_or_create(code=row["code"], defaults=row)
    for row in ADDONS:
        Addon.objects.update_or_create(code=row["code"], defaults=row)
    try:
        PlanPrice = apps.get_model("control", "PlanPrice")
        AddonPrice = apps.get_model("control", "AddonPrice")
    except LookupError:
        return
    for plan in Plan.objects.all():
        for cadence, amount in cycle_amounts(plan.monthly_price).items():
            PlanPrice.objects.update_or_create(
                plan=plan,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )
    for addon in Addon.objects.all():
        for cadence, amount in cycle_amounts(addon.amount).items():
            AddonPrice.objects.update_or_create(
                addon=addon,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )


def assign_plan_labels(apps, schema_editor=None):
    """Copy the free-text plan onto plan_fk. Unknown labels become unassigned."""
    Tenant = apps.get_model("control", "Tenant")
    Plan = apps.get_model("control", "Plan")
    plans = {plan.code: plan for plan in Plan.objects.all()}
    unassigned = plans[UNASSIGNED]
    for tenant in Tenant.objects.all().iterator():
        tenant.plan_fk = plans.get(plan_code_for_label(tenant.plan), unassigned)
        tenant.save(update_fields=["plan_fk"])
