"""Operator dashboard. These views write jobs.

The health action is the one request that opens a tenant database, and only
for the slug in that URL. List pages stay on the control database.
"""

import csv
from datetime import timedelta

from django.conf import settings
from django.contrib import messages
from django.db import IntegrityError, transaction
from django.db.models import Count, OuterRef, Prefetch, Q, Subquery
from django.http import HttpResponse, HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect
from django.template.response import TemplateResponse
from django.utils import timezone
from django.views.decorators.http import require_http_methods, require_POST

from control.audit import public_audit_detail, record_operator_action
from control.health import tenant_health as run_tenant_health
from control.heartbeat import provisioner_notice
from control.billing import (
    BillingError,
    issue_invoice,
    mark_paid,
    mark_past_due,
    subscription_changed,
    void_invoice,
)
from control.auth import (
    current_operator,
    login_operator,
    logout_operator,
    operator_required,
    staff_required,
)
from control.forms import (
    AddonCatalogForm,
    DeleteConfirmForm,
    LoginForm,
    OperatorCreateForm,
    OperatorPasswordForm,
    PlanCatalogForm,
    QuoteForm,
    RestoreForm,
    SubscriptionForm,
    SuspendForm,
    TenantCreateForm,
    TenantQuotaForm,
)
from control.lockout import (
    INVALID_MESSAGE,
    LOCKED_MESSAGE,
    clear_failures,
    is_locked,
    record_failure,
)
from horilla.client_ip import client_ip
from control.setup_access import (
    SetupAccessError,
    consume_setup_password,
    invite_state,
    regenerate_setup_password,
    stage_setup_password,
)
from control.catalog import UNASSIGNED, sellable_plans
from control.models import (
    Addon,
    Domain,
    Invoice,
    Operator,
    OperatorAudit,
    Plan,
    ProvisionJob,
    Tenant,
    WorkspaceRequest,
)
from control.pricing import lock_subscription, quote, quote_tenant
from control.naming import TenantSlugError
from control.provisioning import (
    ProvisionError,
    enqueue_backup,
    enqueue_create,
    enqueue_delete,
    enqueue_migrate,
    enqueue_purge,
    enqueue_restore,
    enqueue_retry,
    enqueue_resume,
    enqueue_suspend,
)


KPI_WINDOW = timedelta(days=7)
DETAIL_SECTIONS = {"all", "overview", "operations", "access"}


def render_control(request, template, context=None, status=200):
    operator = getattr(request, "operator", None)
    data = {"operator": operator}
    if context:
        data.update(context)
    if operator is not None and "nav_tenant_count" not in data:
        stats = data.get("stats")
        if isinstance(stats, dict) and "total" in stats:
            data["nav_tenant_count"] = stats["total"]
        else:
            data["nav_tenant_count"] = Tenant.objects.count()
    if operator is not None and "nav_attention_count" not in data:
        stats = data.get("stats")
        if isinstance(stats, dict) and "failed_jobs_7d" in stats:
            data["nav_attention_count"] = stats["failed_jobs_7d"]
        else:
            data["nav_attention_count"] = _failed_jobs_last_7_days()
    if operator is not None and "nav_trial_count" not in data:
        stats = data.get("stats")
        if isinstance(stats, dict) and "trialing" in stats:
            data["nav_trial_count"] = stats["trialing"] + stats.get("past_due", 0)
        else:
            data["nav_trial_count"] = Tenant.objects.filter(
                status__in=(Tenant.Status.TRIALING, Tenant.Status.PAST_DUE)
            ).count()
    if operator is not None and "nav_billing_count" not in data:
        data["nav_billing_count"] = Invoice.objects.filter(
            status__in=(Invoice.Status.OPEN, Invoice.Status.PAST_DUE)
        ).count()
    if operator is not None and "nav_request_count" not in data:
        data["nav_request_count"] = WorkspaceRequest.objects.filter(
            status=WorkspaceRequest.Status.NEW
        ).count()
    if "provisioner_notice" not in data:
        try:
            data["provisioner_notice"] = provisioner_notice()
        except Exception:
            data["provisioner_notice"] = ""
    return TemplateResponse(
        request,
        template,
        data,
        using="control",
        status=status,
    )


def _safe_next(raw):
    if not raw or not raw.startswith("/control/") or raw.startswith("//"):
        return "/control/"
    return raw


def _audit_login_failure(operator, email: str, ip: str) -> None:
    """Email and IP only. The password is never written here."""
    record_operator_action(
        operator=operator,
        action=OperatorAudit.Action.OPERATOR_LOGIN_FAILED,
        detail=f"Failed sign-in for {email} from {ip}.",
    )


@require_http_methods(["GET", "POST"])
def login(request):
    if current_operator(request) is not None:
        return redirect(_safe_next(request.GET.get("next")))
    form = LoginForm(request.POST or None)
    error = ""
    if request.method == "POST" and form.is_valid():
        email = form.cleaned_data["email"].strip()
        password = form.cleaned_data["password"]
        ip = client_ip(request) or ""
        operator = Operator.objects.filter(email__iexact=email).first()
        # Inactive accounts are not a login target, same as an unknown email.
        known = operator if operator is not None and operator.is_active else None
        if is_locked(email, ip):
            _audit_login_failure(known, email, ip)
            error = LOCKED_MESSAGE
        elif known is None or not known.check_password(password):
            record_failure(email, ip)
            _audit_login_failure(known, email, ip)
            error = LOCKED_MESSAGE if is_locked(email, ip) else INVALID_MESSAGE
        else:
            clear_failures(email, ip)
            login_operator(request, known)
            record_operator_action(
                operator=known,
                action=OperatorAudit.Action.OPERATOR_LOGIN,
                detail=f"Signed in from {ip}.",
            )
            return redirect(_safe_next(request.POST.get("next") or request.GET.get("next")))
    return render_control(
        request,
        "control/login.html",
        {"form": form, "error": error, "next": request.GET.get("next", "")},
    )


@require_POST
def logout(request):
    logout_operator(request)
    return redirect("control-login")


def directory_queryset(query="", plan=""):
    """Control-database filter for the directory. It does not open a tenant database."""
    qs = Tenant.objects.all()
    plan_code = (plan or "").strip()
    if plan_code:
        qs = qs.filter(plan_fk__code=plan_code)
    needle = (query or "").strip()
    if needle:
        qs = qs.filter(
            Q(name__icontains=needle)
            | Q(slug__icontains=needle)
            | Q(domains__host__icontains=needle)
            | Q(industry__icontains=needle)
            | Q(admin_name__icontains=needle)
            | Q(admin_email__icontains=needle)
            | Q(plan_fk__name__icontains=needle)
            | Q(cadence__icontains=needle)
        ).distinct()
    return qs


def _tenant_rows(query="", plan=""):
    last_job = ProvisionJob.objects.filter(tenant=OuterRef("pk")).order_by("-pk")
    last_backup = (
        ProvisionJob.objects.filter(
            tenant=OuterRef("pk"),
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
        )
        .order_by("-finished_at", "-pk")
    )
    tenants = (
        directory_queryset(query, plan).select_related("plan_fk")
        .annotate(
            last_job_kind=Subquery(last_job.values("kind")[:1]),
            last_job_status=Subquery(last_job.values("status")[:1]),
            last_backup_at=Subquery(last_backup.values("finished_at")[:1]),
        )
        .prefetch_related(
            Prefetch("domains", queryset=Domain.objects.order_by("-is_primary", "host"))
        )
        .order_by("name")
    )
    rows = []
    for tenant in tenants:
        primary = ""
        for domain in tenant.domains.all():
            if domain.is_primary:
                primary = domain.host
                break
        if tenant.last_job_kind:
            last_job_label = f"{tenant.last_job_kind} {tenant.last_job_status}"
        else:
            last_job_label = ""
        rows.append(
            {
                "tenant": tenant,
                "primary_host": primary,
                "last_job": last_job_label,
                "last_backup_at": tenant.last_backup_at,
                "needs_setup": bool(tenant.setup_password_encrypted),
                "seat_pct": _usage_pct(tenant.active_seats, tenant.seat_limit),
                "storage_pct": _usage_pct(tenant.used_storage_gb, tenant.storage_limit_gb),
            }
        )
    return rows


def _failed_jobs_last_7_days(now=None):
    cutoff = (now or timezone.now()) - KPI_WINDOW
    return (
        ProvisionJob.objects.filter(status=ProvisionJob.Status.FAILED)
        .filter(
            Q(finished_at__gte=cutoff)
            | Q(finished_at__isnull=True, started_at__gte=cutoff)
        )
        .count()
    )


def _summarize(rows, *, now=None, failed_jobs_7d=0):
    cutoff = (now or timezone.now()) - KPI_WINDOW
    summary = {
        "total": len(rows),
        "active": 0,
        "trialing": 0,
        "past_due": 0,
        "provisioning": 0,
        "suspended": 0,
        "failed": 0,
        "deleting": 0,
        "deleted": 0,
        "needs_setup": 0,
        "failed_jobs_7d": failed_jobs_7d,
        "backup_stale": 0,
        "no_backup": 0,
        "old_backup": 0,
    }
    for row in rows:
        tenant = row["tenant"]
        status = tenant.status
        if status in summary:
            summary[status] += 1
        if row["needs_setup"]:
            summary["needs_setup"] += 1
        if status != Tenant.Status.DELETED:
            last_backup_at = row["last_backup_at"]
            if last_backup_at is None:
                summary["no_backup"] += 1
                summary["backup_stale"] += 1
            elif last_backup_at < cutoff:
                summary["old_backup"] += 1
                summary["backup_stale"] += 1
    return summary


def _visible_rows(rows, status):
    if status == "setup":
        return [row for row in rows if row["needs_setup"]]
    if status:
        return [row for row in rows if row["tenant"].status == status]
    return rows


@operator_required
@require_http_methods(["GET"])
def tenant_list(request):
    now = timezone.now()
    query = (request.GET.get("q") or "").strip()
    plan_filter = (request.GET.get("plan") or "").strip()
    rows = _tenant_rows(query, plan_filter)
    failed_jobs_7d = _failed_jobs_last_7_days(now=now)
    directory = _summarize(rows, now=now, failed_jobs_7d=failed_jobs_7d)
    if query or plan_filter:
        platform = _summarize(
            _tenant_rows(),
            now=now,
            failed_jobs_7d=failed_jobs_7d,
        )
    else:
        platform = directory
    status = (request.GET.get("status") or "").strip()
    allowed = {choice.value for choice in Tenant.Status} | {"setup"}
    if status not in allowed:
        status = ""
    status_tabs = [
        {"id": "", "label": "All", "count": directory["total"]},
        {"id": Tenant.Status.ACTIVE, "label": "Active", "count": directory["active"]},
        {"id": Tenant.Status.TRIALING, "label": "Trialing", "count": directory["trialing"]},
        {"id": Tenant.Status.PAST_DUE, "label": "Past due", "count": directory["past_due"]},
        {
            "id": Tenant.Status.PROVISIONING,
            "label": "Provisioning",
            "count": directory["provisioning"],
        },
        {
            "id": Tenant.Status.SUSPENDED,
            "label": "Suspended",
            "count": directory["suspended"],
        },
        {"id": Tenant.Status.FAILED, "label": "Failed", "count": directory["failed"]},
    ]
    return render_control(
        request,
        "control/tenant_list.html",
        {
            "rows": _visible_rows(rows, status),
            "stats": platform,
            "status_tabs": status_tabs,
            "query": query,
            "plan_filter": plan_filter,
            "plans": Plan.objects.order_by("sort_order", "name"),
            "status_filter": status,
            "activity": ProvisionJob.objects.select_related("tenant").order_by("-pk")[:8],
            "nav_tenant_count": platform["total"],
            "nav_trial_count": platform["trialing"] + platform["past_due"],
        },
    )


@operator_required
@require_http_methods(["GET", "POST"])
def plans(request):
    sellable = list(sellable_plans().prefetch_related("prices"))
    for plan in sellable:
        plan.active_tenants = plan.tenants.exclude(status=Tenant.Status.DELETED).count()
        plan.cycle = {row.cadence: row.unit_rupees for row in plan.prices.all()}
    addons = list(
        Addon.objects.filter(is_active=True)
        .prefetch_related("prices", "compatible_plans")
        .order_by("sort_order", "name")
    )
    managed_plans = list(
        Plan.objects.exclude(code=UNASSIGNED).prefetch_related("prices").order_by("sort_order", "code")
    )
    managed_addons = list(
        Addon.objects.prefetch_related("prices", "compatible_plans").order_by("sort_order", "name")
    )
    form = QuoteForm(request.POST or None)
    quoted = None
    if request.method == "POST" and form.is_valid():
        chosen = form.cleaned_data["plan"]
        quoted = quote(
            chosen,
            form.cleaned_data["cadence"],
            form.cleaned_data["seats"],
            [addon.code for addon in form.cleaned_data["addons"]],
        )
    elif sellable and not form.is_bound:
        growth = next((plan for plan in sellable if plan.code == "growth"), sellable[0])
        quoted = quote(growth, Tenant.Cadence.ANNUAL, 10, [])
    catalog = {
        "plans": {
            plan.code: {
                "monthly": plan.cycle.get("monthly", plan.monthly_price),
                "semiannual": plan.cycle.get("semiannual", plan.monthly_price * 6),
                "annual": plan.cycle.get("annual", 0),
                "setup": plan.setup_fee_rupees,
            }
            for plan in sellable
        },
        "addons": {
            addon.code: {
                "monthly": next((row.unit_rupees for row in addon.prices.all() if row.cadence == "monthly"), addon.amount),
                "semiannual": next((row.unit_rupees for row in addon.prices.all() if row.cadence == "semiannual"), addon.amount * 6),
                "annual": next((row.unit_rupees for row in addon.prices.all() if row.cadence == "annual"), 0),
                "per_seat": addon.per_seat,
                "plans": [plan.code for plan in addon.compatible_plans.all()],
                "required": addon.required,
            }
            for addon in addons
        },
    }
    return render_control(
        request,
        "control/plans.html",
        {
            "plans": sellable,
            "addons": addons,
            "managed_plans": managed_plans,
            "managed_addons": managed_addons,
            "form": form,
            "quote": quoted,
            "annual": Tenant.Cadence.ANNUAL,
            "catalog_json": catalog,
        },
    )


def _catalog_response(request, template, form, title):
    return render_control(
        request,
        template,
        {"form": form, "title": title},
    )


def _cycle_prices(obj, monthly_attr: str) -> str:
    # Query the price rows directly. A prefetched plan still holds the prices
    # from before this save, and the audit must record the values just written.
    related = obj.prices
    rows = related.model.objects.filter(**{related.field.name: obj})
    prices = {row.cadence: row.unit_rupees for row in rows}
    monthly = prices.get("monthly", getattr(obj, monthly_attr, 0) or 0)
    return (
        f"monthly {monthly}, semiannual {prices.get('semiannual', 0)}, "
        f"annual {prices.get('annual', 0)}"
    )


def _audit_catalog(request, kind: str, code: str, before: str, after: str) -> None:
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.CATALOG_UPDATE,
        detail=f"{kind} {code}: {before} -> {after}",
    )


@staff_required
@require_http_methods(["GET", "POST"])
def plan_create(request):
    form = PlanCatalogForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        plan = form.save()
        _audit_catalog(request, "plan", plan.code, "none", _cycle_prices(plan, "monthly_price"))
        messages.success(request, f"Saved plan {plan.name}.")
        return redirect("control-plans")
    return _catalog_response(request, "control/plan_form.html", form, "New plan")


@staff_required
@require_http_methods(["GET", "POST"])
def plan_edit(request, code):
    plan = get_object_or_404(Plan.objects.exclude(code=UNASSIGNED).prefetch_related("prices"), code=code)
    form = PlanCatalogForm(request.POST or None, instance=plan)
    before = _cycle_prices(plan, "monthly_price")
    if request.method == "POST" and form.is_valid():
        saved = form.save()
        _audit_catalog(request, "plan", saved.code, before, _cycle_prices(saved, "monthly_price"))
        messages.success(request, f"Saved plan {plan.name}.")
        return redirect("control-plans")
    return _catalog_response(request, "control/plan_form.html", form, plan.name)


@staff_required
@require_POST
def plan_delete(request, code):
    plan = get_object_or_404(Plan.objects.exclude(code=UNASSIGNED), code=code)
    prices = _cycle_prices(plan, "monthly_price")
    if plan.tenants.exists():
        plan.status = Plan.Status.ARCHIVED
        plan.is_active = False
        plan.save(update_fields=["status", "is_active"])
        _audit_catalog(request, "plan", plan.code, prices, "archived")
        messages.success(request, f"{plan.name} is archived. Tenants already on it keep their locked price.")
    else:
        _audit_catalog(request, "plan", code, prices, "deleted")
        plan.delete()
        messages.success(request, f"Deleted plan {code}.")
    return redirect("control-plans")


@staff_required
@require_http_methods(["GET", "POST"])
def addon_create(request):
    form = AddonCatalogForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        addon = form.save()
        _audit_catalog(request, "add-on", addon.code, "none", _cycle_prices(addon, "amount"))
        messages.success(request, f"Saved add-on {addon.name}.")
        return redirect("control-plans")
    return _catalog_response(request, "control/addon_form.html", form, "New add-on")


@staff_required
@require_http_methods(["GET", "POST"])
def addon_edit(request, code):
    addon = get_object_or_404(
        Addon.objects.prefetch_related("prices", "compatible_plans"),
        code=code,
    )
    form = AddonCatalogForm(request.POST or None, instance=addon)
    before = _cycle_prices(addon, "amount")
    if request.method == "POST" and form.is_valid():
        saved = form.save()
        _audit_catalog(request, "add-on", saved.code, before, _cycle_prices(saved, "amount"))
        messages.success(request, f"Saved add-on {addon.name}.")
        return redirect("control-plans")
    return _catalog_response(request, "control/addon_form.html", form, addon.name)


@staff_required
@require_POST
def addon_delete(request, code):
    addon = get_object_or_404(Addon, code=code)
    prices = _cycle_prices(addon, "amount")
    if addon.subscriptions.exists():
        addon.is_active = False
        addon.save(update_fields=["is_active"])
        _audit_catalog(request, "add-on", addon.code, prices, "deactivated")
        messages.success(request, f"{addon.name} is inactive. Subscriptions that already include it keep the locked price.")
    else:
        _audit_catalog(request, "add-on", code, prices, "deleted")
        addon.delete()
        messages.success(request, f"Deleted add-on {code}.")
    return redirect("control-plans")


def _invoice_status(raw):
    status = (raw or "").strip()
    if status in {choice.value for choice in Invoice.Status}:
        return status
    return ""


def _billing_context(status="", error=""):
    billable = list(
        Tenant.objects.filter(
            status__in=(Tenant.Status.ACTIVE, Tenant.Status.PAST_DUE)
        )
        .select_related("plan_fk")
        .prefetch_related("addons")
    )
    plans = list(sellable_plans())
    grouped = {plan.code: [] for plan in plans}
    for tenant in billable:
        code = tenant.plan_fk.code if tenant.plan_fk_id else ""
        if code in grouped:
            grouped[code].append(tenant)
    tiers = []
    total_monthly = 0
    for plan in plans:
        members = grouped.get(plan.code, [])
        monthly = 0
        seats = 0
        for tenant in members:
            monthly += quote_tenant(tenant).total_monthly
            seats += tenant.seat_limit
        total_monthly += monthly
        tiers.append(
            {
                "plan": plan,
                "count": len(members),
                "seats": seats,
                "monthly": monthly,
            }
        )
    for row in tiers:
        row["share"] = round((row["monthly"] / total_monthly) * 100) if total_monthly else 0
    trials = []
    for tenant in (
        Tenant.objects.filter(status=Tenant.Status.TRIALING)
        .select_related("plan_fk")
        .prefetch_related("addons")
        .order_by("trial_ends_at", "name")
    ):
        monthly = 0
        if tenant.plan_fk_id:
            monthly = quote_tenant(tenant).total_monthly
        trials.append({"tenant": tenant, "monthly": monthly})
    invoices = Invoice.objects.select_related("tenant").order_by("-issued_on", "-pk")
    if status:
        invoices = invoices.filter(status=status)
    return {
        "tiers": tiers,
        "total_monthly": total_monthly,
        "trials": trials,
        "invoices": list(invoices),
        "invoice_status": status,
        "billing_error": error,
        "invoice_tabs": [
            {"id": "", "label": "All"},
            {"id": Invoice.Status.OPEN, "label": "Open"},
            {"id": Invoice.Status.PAST_DUE, "label": "Past due"},
            {"id": Invoice.Status.PAID, "label": "Paid"},
            {"id": Invoice.Status.VOID, "label": "Void"},
        ],
    }


@operator_required
@require_http_methods(["GET"])
def billing(request):
    status = _invoice_status(request.GET.get("status"))
    return render_control(request, "control/billing.html", _billing_context(status))


@operator_required
@require_http_methods(["GET"])
def billing_export(request):
    status = _invoice_status(request.GET.get("status"))
    invoices = Invoice.objects.select_related("tenant").order_by("-issued_on", "-pk")
    if status:
        invoices = invoices.filter(status=status)
    response = HttpResponse(content_type="text/csv")
    response["Content-Disposition"] = 'attachment; filename="invoices.csv"'
    writer = csv.writer(response)
    writer.writerow(
        [
            "invoice_id",
            "tenant_slug",
            "period",
            "plan",
            "seats",
            "amount_rupees",
            "status",
            "issued",
            "due",
        ]
    )
    for invoice in invoices:
        writer.writerow(
            [
                invoice.pk,
                _csv_cell(invoice.tenant.slug),
                _csv_cell(invoice.period_label),
                _csv_cell(invoice.plan_code),
                invoice.seat_count,
                invoice.amount_rupees,
                invoice.status,
                invoice.issued_on.isoformat(),
                invoice.due_on.isoformat(),
            ]
        )
    return response


def _csv_cell(value) -> str:
    text = "" if value is None else str(value)
    if text[:1] in ("=", "+", "-", "@"):
        return "'" + text
    return text


def _invoice_action(request, pk, change):
    invoice = get_object_or_404(Invoice.objects.select_related("tenant"), pk=pk)
    status = _invoice_status(request.POST.get("status"))
    try:
        change(invoice)
    except BillingError as exc:
        return render_control(
            request,
            "control/billing.html",
            _billing_context(status, error=str(exc)),
            status=400,
        )
    if status:
        return redirect(f"/control/billing/?status={status}")
    return redirect("control-billing")


@staff_required
@require_POST
def invoice_past_due(request, pk):
    return _invoice_action(
        request, pk, lambda invoice: mark_past_due(invoice, request.operator)
    )


@staff_required
@require_POST
def invoice_paid(request, pk):
    return _invoice_action(
        request, pk, lambda invoice: mark_paid(invoice, request.operator)
    )


@staff_required
@require_POST
def invoice_void(request, pk):
    return _invoice_action(
        request,
        pk,
        lambda invoice: void_invoice(invoice, request.operator),
    )


@operator_required
@require_http_methods(["GET"])
def audit(request):
    selected = (request.GET.get("category") or "").strip()
    allowed = {choice.value for choice in OperatorAudit.Category}
    if selected not in allowed:
        selected = ""
    rows = OperatorAudit.objects.select_related("operator").order_by("-created_at", "-pk")
    if selected:
        rows = rows.filter(category=selected)
    rows = list(rows[:500])
    slugs = {row.slug for row in rows if row.slug}
    existing = set(Tenant.objects.filter(slug__in=slugs).values_list("slug", flat=True))
    for row in rows:
        row.detail = public_audit_detail(row.detail)
        row.tenant_exists = bool(row.slug) and row.slug in existing
    return render_control(
        request,
        "control/audit.html",
        {
            "audits": rows,
            "audit_category": selected,
            "audit_tabs": [{"id": "", "label": "All"}]
            + [
                {"id": choice.value, "label": choice.label}
                for choice in OperatorAudit.Category
            ],
        },
    )


@operator_required
@require_http_methods(["GET", "POST"])
def tenant_create(request):
    initial = None
    source = _source_request(request)
    notices = []
    if request.method == "GET":
        code = (request.GET.get("plan") or "").strip().lower()
        if code and code != UNASSIGNED:
            chosen = Plan.objects.filter(code=code, is_active=True).first()
            if chosen is not None:
                initial = {"plan": chosen.code, "seats": chosen.seat_cap or 25}
        if source is not None:
            initial, notices = _initial_from_request(source)
    form = TenantCreateForm(request.POST or None, initial=initial)
    if request.method == "POST" and form.is_valid():
        try:
            with transaction.atomic():
                job = enqueue_create(
                    name=form.cleaned_data["name"],
                    slug=form.cleaned_data["slug"],
                    plan=form.cleaned_data["plan"],
                    cadence=form.cleaned_data["cadence"],
                    seats=form.cleaned_data["seats"],
                    modules={
                        "employee_records": form.cleaned_data["module_employee_records"],
                        "payroll_engine": form.cleaned_data["module_payroll_engine"],
                        "performance_reviews": form.cleaned_data["module_performance_reviews"],
                    },
                    industry=form.cleaned_data["industry"],
                    admin_name=form.cleaned_data["admin_name"],
                    admin_email=form.cleaned_data["admin_email"],
                    start_as_trial=form.cleaned_data["start_as_trial"],
                )
                record_operator_action(
                    operator=request.operator,
                    action=OperatorAudit.Action.CREATE,
                    slug=job.tenant.slug,
                    detail="Queued create.",
                )
        except IntegrityError:
            form.add_error("slug", "A tenant with this slug already exists.")
        except (ProvisionError, TenantSlugError) as exc:
            form.add_error(None, str(exc))
        else:
            if source is not None and source.status == WorkspaceRequest.Status.NEW:
                _mark_request(request, source, WorkspaceRequest.Status.REVIEWED, "provisioned")
            messages.success(request, f"Queued provisioning for {job.tenant.slug}.")
            return redirect("control-tenant-detail", slug=job.tenant.slug)
    return render_control(
        request,
        "control/tenant_form.html",
        {
            "form": form,
            "platform_domain": settings.HORILLA_PLATFORM_DOMAIN,
            "source_request": source,
            "request_notices": notices,
        },
    )


def _source_request(request):
    """The workspace request this form was opened from, if any.

    GET carries it in ``?request=<id>``; the form posts it back as a hidden
    field. A missing or malformed id just means a blank form.
    """
    raw = request.GET.get("request") if request.method == "GET" else request.POST.get("from_request")
    try:
        pk = int(raw)
    except (TypeError, ValueError):
        return None
    return WorkspaceRequest.objects.select_related("plan").filter(pk=pk).first()


def _initial_from_request(row):
    """Form defaults taken from a public request, plus notes for the operator."""
    notices = []
    initial = {
        "name": row.company_name,
        "slug": row.requested_slug,
        "admin_name": row.contact_name,
        "admin_email": row.email,
    }
    plan = None
    if row.plan_id:
        plan = sellable_plans().filter(pk=row.plan_id, is_active=True).first()
        if plan is None:
            notices.append("The plan they picked is no longer sold. Choose one below.")
    if plan is not None:
        initial["plan"] = plan.code
    cap = plan.seat_cap if plan is not None else None
    seats = row.seat_count
    if seats and cap and seats > cap:
        notices.append(
            f"They asked for {seats} employees but {plan.name} allows up to {cap}. "
            "Pick a larger plan or keep the cap."
        )
        seats = cap
    if seats:
        initial["seats"] = seats
    elif plan is not None:
        initial["seats"] = cap or 25
    if Tenant.objects.filter(slug=row.requested_slug).exists():
        notices.append("A tenant with the requested address already exists. Choose another slug.")
    return initial, notices


def _format_bytes(size) -> str:
    amount = int(size or 0)
    if amount < 1024:
        return f"{amount} B"
    if amount < 1024 * 1024:
        return f"{amount / 1024:.1f} KB"
    return f"{amount / (1024 * 1024):.1f} MB"


def _backup_rows(slug):
    """This tenant's dumps for the backups table. Errors stay secret-free."""
    from control.backup import list_dumps

    try:
        dumps = list_dumps(slug)
    except Exception:
        return [], "Backups could not be listed."
    rows = []
    for entry in dumps:
        rows.append(
            {
                "name": entry["name"],
                "size_label": _format_bytes(entry.get("size")),
                "taken": entry.get("last_modified"),
            }
        )
    return rows, ""


def _job_steps(job):
    raw = job.payload.get("completed_steps") if isinstance(job.payload, dict) else None
    if not isinstance(raw, list):
        return []
    return [str(step) for step in raw if step]


def _detail_context(tenant, delete_error="", restore_error="", remove_error="", active_section="all"):
    domains = list(tenant.domains.order_by("-is_primary", "host"))
    state = invite_state(tenant)
    primary_host = next((domain.host for domain in domains if domain.is_primary), "")
    signup_url = ""
    if state == "pending":
        host = primary_host or f"{tenant.slug}.{settings.HORILLA_PLATFORM_DOMAIN}"
        signup_url = f"http://{host}/login/"
    backup_rows, dumps_error = _backup_rows(tenant.slug)
    job_rows = []
    watch_jobs = tenant.status == Tenant.Status.PROVISIONING
    for job in tenant.jobs.order_by("-pk"):
        if job.status in {ProvisionJob.Status.QUEUED, ProvisionJob.Status.RUNNING}:
            watch_jobs = True
        job_rows.append({"job": job, "steps": _job_steps(job)})
    section = active_section if active_section in DETAIL_SECTIONS else "all"
    if delete_error or restore_error or remove_error:
        section = "operations"
    return {
        "tenant": tenant,
        "domains": domains,
        "jobs": job_rows,
        "audits": _public_audits(tenant.slug),
        "delete_form": DeleteConfirmForm(),
        "backup_rows": backup_rows,
        "dumps_error": dumps_error,
        "delete_error": delete_error,
        "restore_error": restore_error,
        "remove_error": remove_error,
        "can_purge": tenant.status
        in ("failed", "provisioning", "deleting", "deleted"),
        "invite_state": state,
        "revealed_setup_password": "",
        "signup_url": signup_url,
        "watch_jobs": watch_jobs,
        "primary_host": primary_host,
        "active_section": section,
        "quota_form": TenantQuotaForm(tenant=tenant),
        "seat_pct": _usage_pct(tenant.active_seats, tenant.seat_limit),
        "storage_pct": _usage_pct(tenant.used_storage_gb, tenant.storage_limit_gb),
        "suspend_form": SuspendForm(),
        "subscription_form": SubscriptionForm(tenant=tenant),
        "can_convert": _can_convert(tenant),
    }


def _public_audits(slug):
    rows = list(
        OperatorAudit.objects.filter(slug=slug)
        .select_related("operator")
        .order_by("-created_at")[:12]
    )
    for row in rows:
        row.detail = public_audit_detail(row.detail)
    return rows


def _usage_pct(used, limit) -> int:
    if not limit:
        return 0
    return min(100, round((used / limit) * 100))


@operator_required
@require_http_methods(["GET"])
def tenant_detail(request, slug):
    tenant = get_object_or_404(Tenant.objects.select_related("plan_fk"), slug=slug)
    section = (request.GET.get("section") or "all").strip().lower()
    context = _detail_context(tenant, active_section=section)
    context["revealed_setup_password"] = consume_setup_password(request, slug)
    return render_control(request, "control/tenant_detail.html", context)


@staff_required
@require_POST
def tenant_setup_password(request, slug):
    """Replace a pending setup password and reveal the new one on the next GET."""
    tenant = get_object_or_404(Tenant, slug=slug)
    try:
        plain = regenerate_setup_password(tenant)
    except SetupAccessError:
        messages.error(request, "The setup password has already been cleared.")
        return redirect("control-tenant-detail", slug=slug)
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.SETUP_PASSWORD_RESET,
        slug=tenant.slug,
        detail="Regenerated the setup password.",
    )
    stage_setup_password(request, tenant.slug, plain)
    return redirect(f"/control/tenants/{tenant.slug}/?section=access")


@operator_required
@require_POST
def tenant_health(request, slug):
    """Run the four checks for this slug. The directory never calls this."""
    tenant = get_object_or_404(Tenant.objects.select_related("plan_fk"), slug=slug)
    context = _detail_context(tenant, active_section="operations")
    context["health_lines"] = run_tenant_health(tenant)
    return render_control(request, "control/tenant_detail.html", context)


@operator_required
@require_POST
def tenant_quota(request, slug):
    tenant = get_object_or_404(Tenant.objects.select_related("plan_fk"), slug=slug)
    before = (
        tenant.seat_limit,
        tenant.storage_limit_gb,
        tenant.module_employee_records,
        tenant.module_payroll_engine,
        tenant.module_performance_reviews,
    )
    form = TenantQuotaForm(request.POST, tenant=tenant)
    if not form.is_valid():
        context = _detail_context(tenant, active_section="overview")
        context["quota_form"] = form
        return render_control(request, "control/tenant_detail.html", context)
    tenant.seat_limit = form.cleaned_data["seat_limit"]
    tenant.storage_limit_gb = form.cleaned_data["storage_limit_gb"]
    tenant.module_employee_records = form.cleaned_data["module_employee_records"]
    tenant.module_payroll_engine = form.cleaned_data["module_payroll_engine"]
    tenant.module_performance_reviews = form.cleaned_data["module_performance_reviews"]
    tenant.save(
        update_fields=[
            "seat_limit",
            "storage_limit_gb",
            "module_employee_records",
            "module_payroll_engine",
            "module_performance_reviews",
        ]
    )
    if (tenant.seat_limit, tenant.storage_limit_gb) != before[:2]:
        record_operator_action(
            operator=request.operator,
            action=OperatorAudit.Action.QUOTA_UPDATE,
            slug=tenant.slug,
            detail=(
                f"seats {before[0]} -> {tenant.seat_limit}; "
                f"storage_gb {before[1]} -> {tenant.storage_limit_gb}"
            ),
        )
    modules_after = (
        tenant.module_employee_records,
        tenant.module_payroll_engine,
        tenant.module_performance_reviews,
    )
    if modules_after != before[2:]:
        record_operator_action(
            operator=request.operator,
            action=OperatorAudit.Action.MODULE_UPDATE,
            slug=tenant.slug,
            detail=(
                f"employee_records {before[2]} -> {modules_after[0]}; "
                f"payroll_engine {before[3]} -> {modules_after[1]}; "
                f"performance_reviews {before[4]} -> {modules_after[2]}"
            ),
        )
    if (
        tenant.seat_limit != before[0]
        and tenant.plan_fk_id
        and tenant.status in (Tenant.Status.ACTIVE, Tenant.Status.PAST_DUE)
    ):
        issue_invoice(tenant, request.operator)
    messages.success(request, f"Saved limits for {tenant.slug}.")
    return redirect(f"/control/tenants/{tenant.slug}/?section=overview")


def _queue(request, tenant, action, job):
    record_operator_action(
        operator=request.operator,
        action=action,
        slug=tenant.slug,
        detail=f"Queued {job.kind}.",
    )
    messages.success(request, f"Queued {job.kind} job for {tenant.slug}.")
    return redirect("control-tenant-detail", slug=tenant.slug)


def _can_convert(tenant):
    if tenant.status == Tenant.Status.TRIALING:
        return True
    return tenant.status == Tenant.Status.PAST_DUE and tenant.trial_ends_at is not None


def _operation_rejected(request, tenant, message):
    context = _detail_context(tenant, active_section="operations")
    context["action_error"] = str(message)
    return render_control(
        request,
        "control/tenant_detail.html",
        context,
        status=400,
    )


@operator_required
@require_POST
def tenant_convert(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    if not _can_convert(tenant):
        context = _detail_context(tenant, active_section="overview")
        context["convert_error"] = "Only a trial can be converted."
        return render_control(request, "control/tenant_detail.html", context, status=400)
    before = tenant.trial_ends_at
    with transaction.atomic():
        tenant.status = Tenant.Status.ACTIVE
        tenant.trial_ends_at = None
        tenant.save(update_fields=["status", "trial_ends_at"])
        record_operator_action(
            operator=request.operator,
            action=OperatorAudit.Action.TRIAL_CONVERT,
            slug=tenant.slug,
            detail=f"trial_ends_at {before} -> cleared",
        )
        issue_invoice(tenant, request.operator)
    messages.success(request, f"{tenant.slug} is active.")
    return redirect(f"/control/tenants/{tenant.slug}/?section=overview")


@operator_required
@require_POST
def tenant_subscription(request, slug):
    tenant = get_object_or_404(
        Tenant.objects.select_related("plan_fk").prefetch_related("addons"),
        slug=slug,
    )
    if tenant.status not in (Tenant.Status.ACTIVE, Tenant.Status.PAST_DUE):
        context = _detail_context(tenant, active_section="overview")
        context["subscription_error"] = "Only an active or past-due tenant can change subscription."
        return render_control(request, "control/tenant_detail.html", context, status=400)
    form = SubscriptionForm(request.POST, tenant=tenant)
    if not form.is_valid():
        context = _detail_context(tenant, active_section="overview")
        context["subscription_form"] = form
        return render_control(request, "control/tenant_detail.html", context, status=400)
    plan = form.cleaned_data["plan"]
    cadence = form.cleaned_data["cadence"]
    addons = list(form.cleaned_data["addons"])
    changed = subscription_changed(tenant, plan, cadence, [addon.code for addon in addons])
    with transaction.atomic():
        tenant.plan_fk = plan
        tenant.cadence = cadence
        tenant.save(update_fields=["plan_fk", "cadence"])
        tenant.addons.set(addons)
        if changed:
            lock_subscription(tenant)
            issue_invoice(tenant, request.operator)
    messages.success(request, f"Saved the subscription for {tenant.slug}.")
    return redirect(f"/control/tenants/{tenant.slug}/?section=overview")


@operator_required
@require_POST
def tenant_suspend(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    form = SuspendForm(request.POST)
    if not form.is_valid():
        context = _detail_context(tenant, active_section="operations")
        context["suspend_form"] = form
        return render_control(request, "control/tenant_detail.html", context, status=400)
    try:
        job = enqueue_suspend(tenant, form.cleaned_data["reason"])
    except ProvisionError as exc:
        return _operation_rejected(request, tenant, exc)
    return _queue(request, tenant, OperatorAudit.Action.SUSPEND, job)


@operator_required
@require_POST
def tenant_resume(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    try:
        job = enqueue_resume(tenant)
    except ProvisionError as exc:
        return _operation_rejected(request, tenant, exc)
    return _queue(request, tenant, OperatorAudit.Action.RESUME, job)


@operator_required
@require_POST
def tenant_backup(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    try:
        job = enqueue_backup(tenant)
    except ProvisionError as exc:
        return _operation_rejected(request, tenant, exc)
    return _queue(request, tenant, OperatorAudit.Action.BACKUP, job)


@operator_required
@require_POST
def tenant_migrate(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    try:
        job = enqueue_migrate(tenant)
    except ProvisionError as exc:
        return _operation_rejected(request, tenant, exc)
    return _queue(request, tenant, OperatorAudit.Action.MIGRATE, job)


@operator_required
@require_POST
def tenant_retry(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    try:
        job = enqueue_retry(tenant)
    except ProvisionError as exc:
        return _operation_rejected(request, tenant, exc)
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.CREATE,
        slug=tenant.slug,
        detail="Queued retry.",
    )
    messages.success(request, f"Retry queued for {tenant.slug}.")
    return redirect("control-tenant-detail", slug=tenant.slug)


@staff_required
@require_POST
def tenant_restore(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    from control.backup import list_dumps

    try:
        dumps = list_dumps(tenant.slug)
    except Exception:
        dumps = []
    form = RestoreForm(dumps, request.POST)
    if not form.is_valid():
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, restore_error="Dump name is not valid."),
            status=400,
        )
    try:
        job = enqueue_restore(tenant, form.cleaned_data["dump_name"])
    except ProvisionError as exc:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, restore_error=str(exc)),
            status=400,
        )
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.RESTORE,
        slug=tenant.slug,
        detail=f"Queued restore of {form.cleaned_data['dump_name']}.",
    )
    messages.success(request, "Restore job queued.")
    return redirect("control-tenant-detail", slug=tenant.slug)


@staff_required
@require_POST
def tenant_delete(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    form = DeleteConfirmForm(request.POST)
    typed = form.cleaned_data.get("confirm_slug", "") if form.is_valid() else ""
    if typed != tenant.slug:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, delete_error="Type the tenant slug to confirm delete."),
            status=400,
        )
    try:
        job = enqueue_delete(tenant, typed)
    except ProvisionError as exc:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, delete_error=str(exc)),
            status=400,
        )
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.DELETE,
        slug=tenant.slug,
        detail=f"Queued {job.kind}.",
    )
    messages.success(request, "Delete job queued.")
    return redirect("control-tenant-detail", slug=tenant.slug)


@staff_required
@require_POST
def tenant_purge(request, slug):
    """Remove a tenant that cannot be provisioned. No dump is taken."""
    tenant = get_object_or_404(Tenant, slug=slug)
    form = DeleteConfirmForm(request.POST)
    typed = form.cleaned_data.get("confirm_slug", "") if form.is_valid() else ""
    if typed != tenant.slug:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(
                tenant,
                remove_error="Type the tenant slug to confirm removal.",
            ),
            status=400,
        )
    try:
        job = enqueue_purge(tenant, typed)
    except ProvisionError as exc:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, remove_error=str(exc)),
            status=400,
        )
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.DELETE,
        slug=tenant.slug,
        detail=f"Queued removal without a dump ({job.pk}).",
    )
    messages.success(
        request,
        f"Removal queued for {tenant.slug}. The record disappears when the job finishes.",
    )
    return redirect("control-tenant-detail", slug=tenant.slug)


@staff_required
@require_http_methods(["GET", "POST"])
def operators(request):
    form = OperatorCreateForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        operator = Operator(
            email=form.cleaned_data["email"],
            is_staff=form.cleaned_data["is_staff"],
            is_active=True,
        )
        operator.set_password(form.cleaned_data["password"])
        try:
            operator.save()
        except IntegrityError:
            form.add_error("email", "An operator with this email already exists.")
        else:
            record_operator_action(
                operator=request.operator,
                action=OperatorAudit.Action.OPERATOR_CREATE,
                detail=f"Created {operator.email}.",
            )
            messages.success(request, f"Created operator {operator.email}.")
            return redirect("control-operators")
    operator_rows = list(Operator.objects.order_by("email"))
    return render_control(
        request,
        "control/operators.html",
        {
            "form": form,
            "operators": operator_rows,
            "operator_count": len(operator_rows),
            "active_operator_count": sum(1 for row in operator_rows if row.is_active),
            "inactive_operator_count": sum(1 for row in operator_rows if not row.is_active),
            "staff_count": sum(1 for row in operator_rows if row.is_active and row.is_staff),
            "password_form": OperatorPasswordForm(request.operator),
        },
    )


@staff_required
@require_POST
def operator_deactivate(request, pk):
    target = get_object_or_404(Operator, pk=pk)
    if not target.is_active:
        return redirect("control-operators")
    if target.is_staff:
        others = Operator.objects.filter(is_active=True, is_staff=True).exclude(pk=target.pk)
        if request.operator.pk == target.pk and not others.exists():
            return HttpResponseForbidden("The last staff operator cannot deactivate themselves.")
    target.is_active = False
    target.save(update_fields=["is_active"])
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.OPERATOR_DEACTIVATE,
        detail=f"Deactivated {target.email}.",
    )
    messages.success(request, f"Deactivated {target.email}.")
    return redirect("control-operators")


@staff_required
@require_POST
def operator_reactivate(request, pk):
    target = get_object_or_404(Operator, pk=pk)
    if target.is_active:
        return redirect("control-operators")
    target.is_active = True
    target.save(update_fields=["is_active"])
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.OPERATOR_REACTIVATE,
        detail=f"Reactivated {target.email}.",
    )
    messages.success(request, f"Reactivated {target.email}.")
    return redirect("control-operators")


@operator_required
@require_http_methods(["GET", "POST"])
def operator_password(request):
    form = OperatorPasswordForm(request.operator, request.POST or None)
    if request.method == "POST" and form.is_valid():
        operator = request.operator
        operator.set_password(form.cleaned_data["new_password"])
        operator.session_version += 1
        operator.save(update_fields=["password", "session_version"])
        login_operator(request, operator)
        record_operator_action(
            operator=operator,
            action=OperatorAudit.Action.OPERATOR_PASSWORD_CHANGE,
            detail="Changed own password.",
        )
        messages.success(request, "Password changed. Other sessions were signed out.")
        return redirect("control-operator-password")
    return render_control(
        request,
        "control/password.html",
        {"form": form},
    )


@operator_required
def workspace_requests(request):
    selected = request.GET.get("status", "")
    allowed = {choice.value for choice in WorkspaceRequest.Status}
    rows = WorkspaceRequest.objects.select_related("plan", "reviewed_by")
    if selected in allowed:
        rows = rows.filter(status=selected)
    rows = list(rows)
    existing = set(
        Tenant.objects.filter(slug__in={row.requested_slug for row in rows}).values_list(
            "slug", flat=True
        )
    )
    for row in rows:
        row.tenant_exists = row.requested_slug in existing
    return render_control(
        request,
        "control/requests.html",
        {
            "rows": rows,
            "status": selected if selected in allowed else "",
            "statuses": WorkspaceRequest.Status,
        },
    )


def _mark_request(request, row, status, detail=""):
    row.status = status
    row.reviewed_at = timezone.now()
    row.reviewed_by = request.operator
    row.save(update_fields=["status", "reviewed_at", "reviewed_by"])
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.REQUEST_UPDATE,
        slug=row.requested_slug,
        detail=f"{row.pk} {detail or status}",
    )


def _set_request_status(request, pk, status):
    row = get_object_or_404(WorkspaceRequest, pk=pk)
    _mark_request(request, row, status)
    messages.success(request, "Request updated.")
    return redirect("control-requests")


@operator_required
@require_POST
def workspace_request_reviewed(request, pk):
    return _set_request_status(request, pk, WorkspaceRequest.Status.REVIEWED)


@operator_required
@require_POST
def workspace_request_dismissed(request, pk):
    return _set_request_status(request, pk, WorkspaceRequest.Status.DISMISSED)
