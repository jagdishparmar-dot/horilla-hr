"""Dashboard URL conf. Tenant hosts do not include this module."""

from django.http import HttpResponseNotFound
from django.urls import path

from control import views
from horilla.urls import health_check, readiness_check


def plain_not_found(request, exception):
    """404 without the DB template loader, which belongs to a tenant."""
    return HttpResponseNotFound("Not found.")


handler404 = "control.urls.plain_not_found"

urlpatterns = [
    path("health/", health_check, name="control-health"),
    path("ready/", readiness_check, name="control-ready"),
    path("control/login/", views.login, name="control-login"),
    path("control/logout/", views.logout, name="control-logout"),
    path("control/", views.tenant_list, name="control-home"),
    path("control/plans/", views.plans, name="control-plans"),
    path("control/plans/new/", views.plan_create, name="control-plan-create"),
    path("control/plans/<slug:code>/edit/", views.plan_edit, name="control-plan-edit"),
    path("control/plans/<slug:code>/delete/", views.plan_delete, name="control-plan-delete"),
    path("control/plans/addons/new/", views.addon_create, name="control-addon-create"),
    path("control/plans/addons/<slug:code>/edit/", views.addon_edit, name="control-addon-edit"),
    path("control/plans/addons/<slug:code>/delete/", views.addon_delete, name="control-addon-delete"),
    path("control/billing/", views.billing, name="control-billing"),
    path("control/billing/export.csv", views.billing_export, name="control-billing-export"),
    path(
        "control/billing/invoices/<int:pk>/past-due/",
        views.invoice_past_due,
        name="control-invoice-past-due",
    ),
    path(
        "control/billing/invoices/<int:pk>/paid/",
        views.invoice_paid,
        name="control-invoice-paid",
    ),
    path(
        "control/billing/invoices/<int:pk>/void/",
        views.invoice_void,
        name="control-invoice-void",
    ),
    path("control/audit/", views.audit, name="control-audit"),
    path("control/tenants/new/", views.tenant_create, name="control-tenant-create"),
    path("control/tenants/<slug:slug>/", views.tenant_detail, name="control-tenant-detail"),
    path(
        "control/tenants/<slug:slug>/health/",
        views.tenant_health,
        name="control-tenant-health",
    ),
    path("control/tenants/<slug:slug>/quota/", views.tenant_quota, name="control-tenant-quota"),
    path("control/tenants/<slug:slug>/convert/", views.tenant_convert, name="control-tenant-convert"),
    path(
        "control/tenants/<slug:slug>/subscription/",
        views.tenant_subscription,
        name="control-tenant-subscription",
    ),
    path("control/tenants/<slug:slug>/suspend/", views.tenant_suspend, name="control-tenant-suspend"),
    path("control/tenants/<slug:slug>/resume/", views.tenant_resume, name="control-tenant-resume"),
    path("control/tenants/<slug:slug>/backup/", views.tenant_backup, name="control-tenant-backup"),
    path("control/tenants/<slug:slug>/migrate/", views.tenant_migrate, name="control-tenant-migrate"),
    path("control/tenants/<slug:slug>/retry/", views.tenant_retry, name="control-tenant-retry"),
    path("control/tenants/<slug:slug>/restore/", views.tenant_restore, name="control-tenant-restore"),
    path("control/tenants/<slug:slug>/delete/", views.tenant_delete, name="control-tenant-delete"),
    path("control/tenants/<slug:slug>/remove/", views.tenant_purge, name="control-tenant-purge"),
    path(
        "control/tenants/<slug:slug>/setup-password/",
        views.tenant_setup_password,
        name="control-tenant-setup-password",
    ),
    path("control/operators/", views.operators, name="control-operators"),
    path(
        "control/operators/password/",
        views.operator_password,
        name="control-operator-password",
    ),
    path(
        "control/operators/<int:pk>/deactivate/",
        views.operator_deactivate,
        name="control-operator-deactivate",
    ),
    path(
        "control/operators/<int:pk>/reactivate/",
        views.operator_reactivate,
        name="control-operator-reactivate",
    ),
]
