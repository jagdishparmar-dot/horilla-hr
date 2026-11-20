"""Public pages on the bare platform host. No tenant database is opened."""

from django.conf import settings
from django.core.cache import cache
from django.http.request import split_domain_port
from django.shortcuts import redirect
from django.template.response import TemplateResponse
from django.views.decorators.http import require_http_methods

from control.catalog import CYCLE_MONTHS, UNASSIGNED, format_inr, sellable_plans
from control.models import Addon, Domain, Plan, Tenant, WorkspaceRequest
from control.naming import TenantSlugError, validate_tenant_slug
from control.pricing import catalog_addon_unit, catalog_plan_unit
from horilla.client_ip import client_ip
from marketing import content
from marketing.forms import WorkspaceLookupForm, WorkspaceRequestForm

REQUEST_LIMIT = 5
REQUEST_WINDOW = 60 * 60
NOT_FOUND = "We could not find that workspace."

CYCLE_LABELS = {
    "monthly": "Monthly",
    "semiannual": "Every 6 months",
    "annual": "Annual",
}


def render_marketing(request, template, context=None, status=200):
    data = {
        "platform_domain": settings.HORILLA_PLATFORM_DOMAIN,
    }
    if context:
        data.update(context)
    return TemplateResponse(
        request,
        template,
        data,
        using="marketing",
        status=status,
    )


def home(request):
    plans = _public_plans()[:3]
    return render_marketing(
        request,
        "marketing/home.html",
        {
            "plans": plans,
            "annual_saving": max((plan["annual_saving"] for plan in plans), default=0),
            "modules": content.MODULES,
            "problems": content.PROBLEMS,
            "bento": content.BENTO,
            "tour": content.TOUR,
            "automations": content.AUTOMATIONS,
            "mobile_points": content.MOBILE_POINTS,
            "outcomes": content.OUTCOMES,
            "segments": content.SEGMENTS,
            "steps": content.STEPS,
            "faqs": content.faqs_for("home"),
        },
    )


def features(request):
    return render_marketing(
        request,
        "marketing/features.html",
        {"modules": content.MODULES, "platform": content.PLATFORM},
    )


def pricing(request):
    plans = _public_plans()
    return render_marketing(
        request,
        "marketing/pricing.html",
        {
            "plans": plans,
            "addons": _public_addons(),
            "faqs": content.faqs_for("pricing"),
            "annual_saving": max((plan["annual_saving"] for plan in plans), default=0),
        },
    )


@require_http_methods(["GET", "POST"])
def sign_in(request):
    form = WorkspaceLookupForm(request.POST or None)
    missing = False
    if request.method == "POST" and form.is_valid():
        target = _routable_login_url(request, form.cleaned_data["slug"])
        if target is None:
            missing = True
        else:
            return redirect(target)
    return render_marketing(
        request,
        "marketing/sign_in.html",
        {"form": form, "missing": missing, "not_found": NOT_FOUND},
    )


@require_http_methods(["GET", "POST"])
def request_workspace(request):
    if request.method == "POST" and _request_is_limited(request):
        form = WorkspaceRequestForm(request.POST)
        form.add_error(None, "Too many requests. Try again later.")
    else:
        form = WorkspaceRequestForm(request.POST or None, initial=_initial_request(request))
        if request.method == "POST" and form.is_valid():
            WorkspaceRequest.objects.create(
                company_name=form.cleaned_data["company_name"],
                contact_name=form.cleaned_data["contact_name"],
                email=form.cleaned_data["email"],
                phone=form.cleaned_data["phone"],
                requested_slug=form.cleaned_data["slug"],
                plan=form.cleaned_data["plan"],
                seat_count=form.cleaned_data["seat_count"],
                message=form.cleaned_data["message"],
            )
            return redirect("marketing-request-sent")
    return render_marketing(
        request,
        "marketing/request.html",
        {"form": form, "steps": content.STEPS[1:]},
    )


def request_sent(request):
    return render_marketing(request, "marketing/request_sent.html")


def _initial_request(request):
    """Preselect the plan named in ``?plan=<code>``. Anything else is ignored."""
    code = (request.GET.get("plan") or "").strip().lower()
    if not code:
        return {}
    plan = sellable_plans().filter(code=code, status=Plan.Status.ACTIVE).first()
    return {"plan": plan.pk} if plan else {}


def _per_month(unit: int, months: int) -> int:
    """Whole rupees per month for a term price, rounded half up."""
    return (int(unit) + months // 2) // months


def _cycle_note(key: str, billed: str) -> str:
    if key == "monthly":
        return "Billed monthly"
    if key == "semiannual":
        return f"{billed} per seat, billed every 6 months"
    return f"{billed} per seat, billed yearly"


def _public_plans():
    plans = (
        Plan.objects.filter(status=Plan.Status.ACTIVE, is_active=True)
        .exclude(code=UNASSIGNED)
        .order_by("sort_order", "code")
    )
    rows = []
    for plan in plans:
        monthly_unit = catalog_plan_unit(plan, "monthly")
        cycles = []
        units = {}
        for key, months in CYCLE_MONTHS.items():
            unit = catalog_plan_unit(plan, key)
            units[key] = unit
            billed = format_inr(unit)
            cycles.append(
                {
                    "key": key,
                    "label": CYCLE_LABELS[key],
                    "months": months,
                    "per_month": format_inr(_per_month(unit, months)),
                    "billed": billed,
                    "note": _cycle_note(key, billed),
                }
            )
        full_year = monthly_unit * 12
        saving = 0
        if full_year and units["annual"] < full_year:
            saving = round(100 * (full_year - units["annual"]) / full_year)
        rows.append(
            {
                "name": plan.name,
                "code": plan.code,
                "description": plan.description,
                "monthly": format_inr(monthly_unit),
                "semiannual": format_inr(units["semiannual"]),
                "annual": format_inr(units["annual"]),
                "cycles": cycles,
                "annual_per_month": cycles[-1]["per_month"],
                "annual_saving": saving,
                "seat_cap": plan.seat_cap,
                "storage_gb_per_seat": plan.storage_gb_per_seat,
                "trial_days": plan.trial_days,
                "setup_fee": format_inr(plan.setup_fee_rupees),
                "has_setup_fee": bool(plan.setup_fee_rupees),
            }
        )
    return rows


def _public_addons():
    rows = []
    for addon in Addon.objects.filter(is_active=True).order_by("sort_order", "name"):
        rows.append(
            {
                "name": addon.name,
                "description": addon.description,
                "monthly": format_inr(catalog_addon_unit(addon, "monthly")),
                "per_seat": addon.per_seat,
            }
        )
    return rows


def _routable_login_url(request, raw_slug):
    try:
        slug = validate_tenant_slug(raw_slug)
    except TenantSlugError:
        return None
    domain = (
        Domain.objects.filter(
            host=f"{slug}.{settings.HORILLA_PLATFORM_DOMAIN}",
            verified=True,
        )
        .select_related("tenant")
        .first()
    )
    if domain is None or domain.tenant.status not in Tenant.ROUTABLE_STATUSES:
        return None
    return _tenant_login_url(request, slug)


def _tenant_login_url(request, slug: str) -> str:
    domain = settings.HORILLA_PLATFORM_DOMAIN
    scheme = "http" if domain == "localhost" else "https"
    _, port = split_domain_port(request.get_host())
    netloc = f"{slug}.{domain}"
    if port:
        netloc = f"{netloc}:{port}"
    return f"{scheme}://{netloc}/login/"


def _request_is_limited(request) -> bool:
    ip = client_ip(request) or "unknown"
    key = f"marketing-request:{ip}"
    count = int(cache.get(key, 0) or 0)
    if count >= REQUEST_LIMIT:
        return True
    cache.set(key, count + 1, REQUEST_WINDOW)
    return False
