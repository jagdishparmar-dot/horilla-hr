"""Bind a request to a tenant database, or reject the host.

With HORILLA_MULTITENANT off, this middleware does nothing so the current
single-database install keeps answering on localhost.
"""

from django.conf import settings
from django.db import connections
from django.http import HttpResponseForbidden, HttpResponseNotFound

from control.context import activate_tenant_alias, clear_tenant_alias
from control.db import ensure_tenant_connection
from control.hosts import request_hostname
from control.models import Domain, Tenant
from horilla.isolation import activate_cache_scope, clear_cache_scope


class TenantMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if not getattr(settings, "HORILLA_MULTITENANT", False):
            return self.get_response(request)

        token = None
        alias = None
        scope_token = None
        try:
            early, token, alias = self._bind(request)
            if request.control_plane:
                scope_token = activate_cache_scope("control")
            elif getattr(request, "tenant", None) is not None:
                scope_token = activate_cache_scope(request.tenant.slug)
            if early is not None:
                return early
            return self.get_response(request)
        finally:
            clear_cache_scope(scope_token)
            clear_tenant_alias(token)
            if alias:
                _close_alias(alias)

    def _bind(self, request):
        request.tenant = None
        request.control_plane = False
        host = request_hostname(request)
        dashboard = (settings.HORILLA_DASHBOARD_HOST or "").lower()
        if host == dashboard:
            request.control_plane = True
            request.urlconf = "control.urls"
            return None, None, None

        domain = (
            Domain.objects.filter(host=host, verified=True)
            .select_related("tenant")
            .first()
        )
        if domain is None:
            return HttpResponseNotFound("Unknown host."), None, None

        tenant = domain.tenant
        if tenant.status != Tenant.Status.ACTIVE:
            return (
                HttpResponseForbidden("This workspace is not available."),
                None,
                None,
            )

        alias = ensure_tenant_connection(tenant)
        token = activate_tenant_alias(alias)
        request.tenant = tenant
        request.urlconf = "horilla.urls"
        return None, token, alias


def _close_alias(alias: str) -> None:
    if alias not in connections.databases:
        return
    connections[alias].close()
