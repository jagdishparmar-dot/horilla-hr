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
    path("control/tenants/new/", views.tenant_create, name="control-tenant-create"),
    path("control/tenants/<slug:slug>/", views.tenant_detail, name="control-tenant-detail"),
    path("control/tenants/<slug:slug>/suspend/", views.tenant_suspend, name="control-tenant-suspend"),
    path("control/tenants/<slug:slug>/resume/", views.tenant_resume, name="control-tenant-resume"),
    path("control/tenants/<slug:slug>/backup/", views.tenant_backup, name="control-tenant-backup"),
    path("control/tenants/<slug:slug>/migrate/", views.tenant_migrate, name="control-tenant-migrate"),
    path("control/tenants/<slug:slug>/restore/", views.tenant_restore, name="control-tenant-restore"),
    path("control/tenants/<slug:slug>/delete/", views.tenant_delete, name="control-tenant-delete"),
    path("control/operators/", views.operators, name="control-operators"),
    path(
        "control/operators/<int:pk>/deactivate/",
        views.operator_deactivate,
        name="control-operator-deactivate",
    ),
]
