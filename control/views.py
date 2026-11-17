"""Operator dashboard. These views write jobs. They do not open tenant databases."""

from django.conf import settings
from django.contrib import messages
from django.db import IntegrityError, transaction
from django.db.models import OuterRef, Prefetch, Subquery
from django.http import HttpResponseForbidden
from django.shortcuts import get_object_or_404, redirect
from django.template.response import TemplateResponse
from django.views.decorators.http import require_http_methods, require_POST

from control.audit import record_operator_action
from control.auth import (
    current_operator,
    login_operator,
    logout_operator,
    operator_required,
    staff_required,
)
from control.forms import (
    DeleteConfirmForm,
    LoginForm,
    OperatorCreateForm,
    RestoreForm,
    TenantCreateForm,
)
from control.crypto import TenantPasswordError
from control.models import Domain, Operator, OperatorAudit, ProvisionJob, Tenant
from control.naming import TenantSlugError
from control.provisioning import (
    ProvisionError,
    enqueue_backup,
    enqueue_create,
    enqueue_delete,
    enqueue_migrate,
    enqueue_restore,
    enqueue_resume,
    enqueue_suspend,
)


def render_control(request, template, context=None, status=200):
    data = {"operator": getattr(request, "operator", None)}
    if context:
        data.update(context)
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


@require_http_methods(["GET", "POST"])
def login(request):
    if current_operator(request) is not None:
        return redirect(_safe_next(request.GET.get("next")))
    form = LoginForm(request.POST or None)
    error = ""
    if request.method == "POST" and form.is_valid():
        email = form.cleaned_data["email"].strip()
        password = form.cleaned_data["password"]
        operator = Operator.objects.filter(email__iexact=email).first()
        if (
            operator is None
            or not operator.is_active
            or not operator.check_password(password)
        ):
            error = "Email or password is not valid."
        else:
            login_operator(request, operator)
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


def _tenant_rows():
    last_job = ProvisionJob.objects.filter(tenant=OuterRef("pk")).order_by("-pk")
    last_backup = (
        ProvisionJob.objects.filter(
            tenant=OuterRef("pk"),
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
        )
        .order_by("-finished_at")
    )
    tenants = (
        Tenant.objects.annotate(
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
            }
        )
    return rows


def _summarize(rows):
    summary = {
        "total": len(rows),
        "active": 0,
        "provisioning": 0,
        "suspended": 0,
        "failed": 0,
        "deleting": 0,
        "deleted": 0,
        "needs_setup": 0,
    }
    for row in rows:
        status = row["tenant"].status
        if status in summary:
            summary[status] += 1
        if row["needs_setup"]:
            summary["needs_setup"] += 1
    return summary


def _visible_rows(rows, query, status):
    visible = rows
    if status == "setup":
        visible = [row for row in visible if row["needs_setup"]]
    elif status:
        visible = [row for row in visible if row["tenant"].status == status]
    if query:
        needle = query.lower()
        visible = [
            row
            for row in visible
            if needle in row["tenant"].name.lower()
            or needle in row["tenant"].slug.lower()
            or needle in (row["primary_host"] or "").lower()
            or needle in (row["tenant"].plan or "").lower()
        ]
    return visible


@operator_required
@require_http_methods(["GET"])
def tenant_list(request):
    rows = _tenant_rows()
    query = (request.GET.get("q") or "").strip()
    status = (request.GET.get("status") or "").strip()
    allowed = {choice.value for choice in Tenant.Status} | {"setup"}
    if status not in allowed:
        status = ""
    return render_control(
        request,
        "control/tenant_list.html",
        {
            "rows": _visible_rows(rows, query, status),
            "stats": _summarize(rows),
            "query": query,
            "status_filter": status,
            "activity": ProvisionJob.objects.select_related("tenant").order_by("-pk")[:8],
        },
    )


@operator_required
@require_http_methods(["GET", "POST"])
def tenant_create(request):
    form = TenantCreateForm(request.POST or None)
    if request.method == "POST" and form.is_valid():
        try:
            with transaction.atomic():
                job = enqueue_create(
                    name=form.cleaned_data["name"],
                    slug=form.cleaned_data["slug"],
                    plan=form.cleaned_data["plan"],
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
            messages.success(request, f"Queued provisioning for {job.tenant.slug}.")
            return redirect("control-tenant-detail", slug=job.tenant.slug)
    return render_control(
        request,
        "control/tenant_form.html",
        {"form": form, "platform_domain": settings.HORILLA_PLATFORM_DOMAIN},
    )


def _job_steps(job):
    raw = job.payload.get("completed_steps") if isinstance(job.payload, dict) else None
    if not isinstance(raw, list):
        return []
    return [str(step) for step in raw if step]


def _detail_context(tenant, delete_error="", restore_error=""):
    domains = list(tenant.domains.order_by("-is_primary", "host"))
    setup_password = ""
    signup_url = ""
    if tenant.setup_password_encrypted:
        try:
            setup_password = tenant.setup_password()
        except TenantPasswordError:
            setup_password = ""
    if setup_password:
        host = next((domain.host for domain in domains if domain.is_primary), "")
        if not host:
            host = f"{tenant.slug}.{settings.HORILLA_PLATFORM_DOMAIN}"
        signup_url = f"http://{host}/login/"
    job_rows = []
    watch_jobs = tenant.status == Tenant.Status.PROVISIONING
    for job in tenant.jobs.order_by("-pk"):
        if job.status in {ProvisionJob.Status.QUEUED, ProvisionJob.Status.RUNNING}:
            watch_jobs = True
        job_rows.append({"job": job, "steps": _job_steps(job)})
    return {
        "tenant": tenant,
        "domains": domains,
        "jobs": job_rows,
        "audits": list(
            OperatorAudit.objects.filter(slug=tenant.slug)
            .select_related("operator")
            .order_by("-created_at")[:12]
        ),
        "delete_form": DeleteConfirmForm(),
        "restore_form": RestoreForm(),
        "delete_error": delete_error,
        "restore_error": restore_error,
        "setup_password": setup_password,
        "signup_url": signup_url,
        "watch_jobs": watch_jobs,
        "primary_host": next((domain.host for domain in domains if domain.is_primary), ""),
    }


@operator_required
@require_http_methods(["GET"])
def tenant_detail(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    return render_control(
        request,
        "control/tenant_detail.html",
        _detail_context(tenant),
    )


def _queue(request, tenant, action, job):
    record_operator_action(
        operator=request.operator,
        action=action,
        slug=tenant.slug,
        detail=f"Queued {job.kind}.",
    )
    messages.success(request, f"Queued {job.kind} job for {tenant.slug}.")
    return redirect("control-tenant-detail", slug=tenant.slug)


@operator_required
@require_POST
def tenant_suspend(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    job = enqueue_suspend(tenant)
    return _queue(request, tenant, OperatorAudit.Action.SUSPEND, job)


@operator_required
@require_POST
def tenant_resume(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    job = enqueue_resume(tenant)
    return _queue(request, tenant, OperatorAudit.Action.RESUME, job)


@operator_required
@require_POST
def tenant_backup(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    job = enqueue_backup(tenant)
    return _queue(request, tenant, OperatorAudit.Action.BACKUP, job)


@operator_required
@require_POST
def tenant_migrate(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    job = enqueue_migrate(tenant)
    return _queue(request, tenant, OperatorAudit.Action.MIGRATE, job)


@operator_required
@require_POST
def tenant_restore(request, slug):
    tenant = get_object_or_404(Tenant, slug=slug)
    form = RestoreForm(request.POST)
    if not form.is_valid():
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, restore_error="Dump name is required."),
        )
    try:
        job = enqueue_restore(tenant, form.cleaned_data["dump_name"])
    except ProvisionError as exc:
        return render_control(
            request,
            "control/tenant_detail.html",
            _detail_context(tenant, restore_error=str(exc)),
        )
    record_operator_action(
        operator=request.operator,
        action=OperatorAudit.Action.RESTORE,
        slug=tenant.slug,
        detail=f"Queued restore of {form.cleaned_data['dump_name']}.",
    )
    messages.success(request, "Restore job queued.")
    return redirect("control-tenant-detail", slug=tenant.slug)


@operator_required
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
