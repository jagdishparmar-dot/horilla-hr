"""
Tenant-scoped JWT authentication for the API.

Why this exists
---------------
Tenant scoping in this project rests on a ContextVar: ``CompanyMiddleware``
resolves the caller's company and calls ``set_selected_company()``, and
``HorillaCompanyManager.get_queryset()`` reads it on every query.

That works for session-authenticated web requests. It does not apply on the
API path, because of ordering:

    MIDDLEWARE          -> CompanyMiddleware runs here, sees AnonymousUser
    view dispatch       -> DRF resolves the JWT here, user becomes known

``CompanyMiddleware._handle()`` returns early for unauthenticated requests, so
a token-authenticated request reaches the view with the ContextVar unset, and
``HorillaCompanyManager`` applies no company predicate when it is unset::

    if not filter_path or not company:
        return qs          # no company context -> no predicate added

This class sets the ContextVar at the moment the user is resolved, which is
the earliest point the company is knowable on a tokened request, so the API
path gets the same manager-level scoping the web path already has.

Scope
-----
This establishes the *manager-level* default scoping only. Per-viewset
``get_queryset`` filtering is still worth adding, because a manager default
can be bypassed by ``_base_manager``, ``entire()`` or raw SQL.
"""

from __future__ import annotations

import logging

from django.conf import settings
from django.utils.translation import gettext_lazy as _
from rest_framework.exceptions import PermissionDenied
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import AuthenticationFailed

from control.context import get_tenant_alias
from horilla.horilla_middlewares import set_selected_company

logger = logging.getLogger(__name__)


def resolve_company_id(user):
    """The company a tokened request should be scoped to, or None.

    Mirrors ``CompanyMiddleware._get_user_default_company``: the employee's
    work-information company. There is no session on an API request, so the
    session's ``selected_company`` (and its "all" mode) has no equivalent
    here -- a token is scoped to the user's own company, which is the
    conservative reading.

    Superusers are left unscoped, matching the web path, where
    ``HorillaCompanyManager`` treats "all" as tenant-wide for them.
    """
    if user is None or not user.is_authenticated:
        return None
    if user.is_superuser:
        return None
    # Query the work-info row rather than traversing user.employee_get:
    # the reverse OneToOne is cached on the user instance, so a user object
    # loaded before its work info was written keeps returning a stale (or
    # null) company. A direct query cannot go stale, and it is one indexed
    # lookup either way.
    try:
        from employee.models import EmployeeWorkInformation

        return (
            EmployeeWorkInformation.objects.filter(
                employee_id__employee_user_id=user.pk
            )
            .values_list("company_id", flat=True)
            .first()
        )
    except Exception:
        # No employee record, no work info, or the app is unavailable.
        # Callers must read None as "cannot place this user", never as
        # "no restriction needed".
        logger.exception("Could not resolve company for user_id=%s", user.pk)
        return None


def stamp_tenant_claim(token):
    """Bind a new token to the tenant selected from the request host."""
    if not getattr(settings, "HORILLA_MULTITENANT", False):
        return token
    alias = get_tenant_alias()
    if not alias or not str(alias).startswith("tenant_"):
        raise AuthenticationFailed(_("No workspace is selected for this token."))
    token["tenant_slug"] = str(alias)[len("tenant_") :]
    return token


class TenantScopedJWTAuthentication(JWTAuthentication):
    """JWTAuthentication that also establishes tenant scope.

    DRF calls ``authenticate()`` during view dispatch, after all middleware.
    Setting the ContextVar here means every queryset built by the view -- and
    by anything it calls -- is company-filtered, without each of the 333
    endpoints having to remember.

    ``CompanyMiddleware.__call__`` resets the ContextVar in a ``finally``, so
    the value set here does not outlive the request even though it is set
    later in the cycle.
    """

    def authenticate(self, request):
        header = self.get_header(request)
        if header is None:
            return None
        raw_token = self.get_raw_token(header)
        if raw_token is None:
            return None
        validated_token = self.get_validated_token(raw_token)
        # The host already selected the database. Reject another tenant's
        # token before that user id is looked up.
        if getattr(settings, "HORILLA_MULTITENANT", False):
            tenant = getattr(request, "tenant", None)
            claimed = validated_token.get("tenant_slug")
            if tenant is None or claimed != tenant.slug:
                raise AuthenticationFailed(
                    _("Token is not valid for this workspace."),
                    code="wrong_tenant",
                )
        user = self.get_user(validated_token)
        company_id = resolve_company_id(user)
        if company_id is not None:
            set_selected_company(company_id)
        elif not user.is_superuser:
            # None means "cannot place this user", never "no restriction".
            # Proceeding would run HorillaCompanyManager with no predicate.
            logger.warning(
                "API request from user_id=%s has no resolvable company; refusing",
                getattr(user, "pk", None),
            )
            raise PermissionDenied(_("This account is not assigned to a company."))
        return user, validated_token
