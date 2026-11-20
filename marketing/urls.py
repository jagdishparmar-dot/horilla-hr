"""Public URL conf. Only the bare platform host includes this module."""

from django.http import HttpResponseNotFound
from django.urls import path

from horilla.urls import health_check
from marketing import views


def plain_not_found(request, exception):
    """404 without the tenant template loader."""
    return HttpResponseNotFound("Not found.")


handler404 = "marketing.urls.plain_not_found"

urlpatterns = [
    path("", views.home, name="marketing-home"),
    path("features/", views.features, name="marketing-features"),
    path("pricing/", views.pricing, name="marketing-pricing"),
    path("sign-in/", views.sign_in, name="marketing-sign-in"),
    path("request/", views.request_workspace, name="marketing-request"),
    path("request/sent/", views.request_sent, name="marketing-request-sent"),
    path("contact-sales/", views.contact_sales, name="marketing-contact-sales"),
    path(
        "contact-sales/sent/",
        views.contact_sales_sent,
        name="marketing-contact-sales-sent",
    ),
    path("health/", health_check, name="marketing-health"),
]
