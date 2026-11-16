"""Dashboard URL conf. Tenant hosts do not include this module."""

from django.http import HttpResponse, HttpResponseNotFound
from django.urls import path

from horilla.urls import health_check, readiness_check


def control_home(request):
    return HttpResponse("Control plane", content_type="text/plain")


def plain_not_found(request, exception):
    """404 without the DB template loader, which belongs to a tenant."""
    return HttpResponseNotFound("Not found.")


handler404 = "control.urls.plain_not_found"

urlpatterns = [
    path("health/", health_check, name="control-health"),
    path("ready/", readiness_check, name="control-ready"),
    path("control/", control_home, name="control-home"),
]
