"""Session cookie name depends on the host.

The dashboard uses ``control_sessionid``. Every other host keeps ``sessionid``.
Both names use the same session store. A cookie set on a tenant host is not
read on the dashboard, and the reverse is also true.

The session also stores the tenant slug it was issued for. Replaying that
cookie on another host does not authenticate, even when both databases have
a user with the same primary key.
"""

import time
from importlib import import_module

from django.conf import settings
from django.contrib.auth import logout
from django.contrib.sessions.backends.base import UpdateError
from django.contrib.sessions.exceptions import SessionInterrupted
from django.contrib.sessions.middleware import SessionMiddleware
from django.utils.cache import patch_vary_headers
from django.utils.http import http_date

from control.auth import session_cookie_name


class SessionMiddleware(SessionMiddleware):
    def __init__(self, get_response):
        super().__init__(get_response)
        engine = import_module(settings.SESSION_ENGINE)
        self.SessionStore = engine.SessionStore

    def process_request(self, request):
        name = session_cookie_name(request)
        request.control_session_cookie_name = name
        session_key = request.COOKIES.get(name)
        request.session = self.SessionStore(session_key)

    def process_response(self, request, response):
        name = getattr(
            request, "control_session_cookie_name", None
        ) or session_cookie_name(request)
        try:
            accessed = request.session.accessed
            modified = request.session.modified
            empty = request.session.is_empty()
        except AttributeError:
            return response
        if name in request.COOKIES and empty:
            response.delete_cookie(
                name,
                path=settings.SESSION_COOKIE_PATH,
                domain=settings.SESSION_COOKIE_DOMAIN,
                samesite=settings.SESSION_COOKIE_SAMESITE,
            )
            need_vary_cookie = True
        else:
            need_vary_cookie = accessed
            if (modified or settings.SESSION_SAVE_EVERY_REQUEST) and not empty:
                if request.session.get_expire_at_browser_close():
                    max_age = None
                    expires = None
                else:
                    max_age = request.session.get_expiry_age()
                    expires_time = time.time() + max_age
                    expires = http_date(expires_time)
                if response.status_code < 500:
                    try:
                        request.session.save()
                    except UpdateError:
                        raise SessionInterrupted(
                            "The request's session was deleted before the "
                            "request completed. The user may have logged "
                            "out in a concurrent request, for example."
                        )
                    response.set_cookie(
                        name,
                        request.session.session_key,
                        max_age=max_age,
                        expires=expires,
                        domain=settings.SESSION_COOKIE_DOMAIN,
                        path=settings.SESSION_COOKIE_PATH,
                        secure=settings.SESSION_COOKIE_SECURE or None,
                        httponly=settings.SESSION_COOKIE_HTTPONLY or None,
                        samesite=settings.SESSION_COOKIE_SAMESITE,
                    )
                    need_vary_cookie = True
        if need_vary_cookie:
            patch_vary_headers(response, ("Cookie",))
        return response


def stamp_tenant_session(sender, request, user, **kwargs):
    """Remember which tenant issued this login. No-op off a tenant host."""
    if request is None or not getattr(settings, "HORILLA_MULTITENANT", False):
        return
    tenant = getattr(request, "tenant", None)
    if tenant is not None:
        request.session["tenant_slug"] = tenant.slug


class TenantSessionMiddleware:
    """Drop a Django login that was issued for a different tenant host."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if getattr(settings, "HORILLA_MULTITENANT", False):
            tenant = getattr(request, "tenant", None)
            user = getattr(request, "user", None)
            if (
                tenant is not None
                and user is not None
                and user.is_authenticated
                and request.session.get("tenant_slug") != tenant.slug
            ):
                logout(request)
        return self.get_response(request)
