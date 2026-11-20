"""Public pages on the bare platform host. No tenant database is opened."""

from django.conf import settings
from django.core.cache import cache
from django.http.request import split_domain_port
from django.shortcuts import redirect
from django.template.response import TemplateResponse
from django.views.decorators.http import require_http_methods

from control.catalog import UNASSIGNED, format_inr, sellable_plans
from control.models import Addon, Domain, Plan, Tenant, WorkspaceRequest
from control.naming import TenantSlugError, validate_tenant_slug
from control.pricing import catalog_addon_unit, catalog_plan_unit
from horilla.client_ip import client_ip
from marketing import content
from marketing.forms import SalesInquiryForm, WorkspaceLookupForm, WorkspaceRequestForm

REQUEST_LIMIT = 5
REQUEST_WINDOW = 60 * 60
NOT_FOUND = "We could not find that workspace."


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
    plans = _public_plans()
    return render_marketing(
        request,
        "marketing/home.html",
        {
            "plans": plans,
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


@require_http_methods(["GET", "POST"])
def contact_sales(request):
    """Enquiry form for plans that show no price. Saved for operators; nothing is provisioned."""
    if request.method == "POST" and _request_is_limited(request):
        form = SalesInquiryForm(request.POST)
        form.add_error(None, "Too many requests. Try again later.")
    else:
        form = SalesInquiryForm(request.POST or None, initial=_initial_request(request))
        if request.method == "POST" and form.is_valid():
            WorkspaceRequest.objects.create(
                kind=WorkspaceRequest.Kind.SALES,
                company_name=form.cleaned_data["company_name"],
                contact_name=form.cleaned_data["contact_name"],
                email=form.cleaned_data["email"],
                phone=form.cleaned_data["phone"],
                plan=form.cleaned_data["plan"],
                seat_count=form.cleaned_data["seat_count"],
                message=form.cleaned_data["message"],
            )
            return redirect("marketing-contact-sales-sent")
    return render_marketing(request, "marketing/contact_sales.html", {"form": form})


def contact_sales_sent(request):
    return render_marketing(request, "marketing/contact_sales_sent.html")


def _initial_request(request):
    """Preselect the plan named in ``?plan=<code>``. Anything else is ignored."""
    code = (request.GET.get("plan") or "").strip().lower()
    if not code:
        return {}
    plan = sellable_plans().filter(code=code, status=Plan.Status.ACTIVE).first()
    return {"plan": plan.pk} if plan else {}


def _public_plans():
    """Plans for the pricing pages.

    A Talk to Sales plan carries no price at all, so a template cannot leak
    one by accident. Its setup fee stays off the page for the same reason.
    """
    plans = (
        Plan.objects.filter(status=Plan.Status.ACTIVE, is_active=True)
        .exclude(code=UNASSIGNED)
        .prefetch_related("features", "included_addons")
        .order_by("sort_order", "code")
    )
    rows = []
    for plan in plans:
        sales = plan.contact_sales
        setup_fee = int(plan.setup_fee_rupees or 0)
        rows.append(
            {
                "name": plan.name,
                "code": plan.code,
                "description": plan.description,
                "contact_sales": sales,
                "price": None if sales else format_inr(catalog_plan_unit(plan, "monthly")),
                "seat_cap": plan.seat_cap,
                "trial_days": plan.trial_days,
                "setup_fee": format_inr(setup_fee),
                "has_setup_fee": bool(setup_fee) and not sales,
                "features": [feature.text for feature in plan.features.all()],
                "included_addons": [
                    addon.name for addon in plan.included_addons.all() if addon.is_active
                ],
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
