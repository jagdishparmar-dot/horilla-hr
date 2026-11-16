"""Operator session. This is not Django's user authentication."""

from functools import wraps

from django.shortcuts import redirect
from django.urls import reverse

from control.models import Operator

CONTROL_SESSION_COOKIE_NAME = "control_sessionid"
SESSION_OPERATOR_ID = "control_operator_id"


def session_cookie_name(request) -> str:
    """Dashboard host only. Tenant hosts keep Django's sessionid cookie."""
    from django.conf import settings

    if getattr(request, "control_plane", False):
        return CONTROL_SESSION_COOKIE_NAME
    return settings.SESSION_COOKIE_NAME


def current_operator(request):
    operator_id = request.session.get(SESSION_OPERATOR_ID)
    if not operator_id:
        return None
    return Operator.objects.filter(pk=operator_id, is_active=True).first()


def login_operator(request, operator) -> None:
    request.session.cycle_key()
    request.session[SESSION_OPERATOR_ID] = operator.pk


def logout_operator(request) -> None:
    request.session.flush()


def operator_required(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        operator = current_operator(request)
        if operator is None:
            login_url = reverse("control-login")
            return redirect(f"{login_url}?next={request.path}")
        request.operator = operator
        return view(request, *args, **kwargs)

    return wrapped


def staff_required(view):
    @wraps(view)
    def wrapped(request, *args, **kwargs):
        @operator_required
        def inner(req, *a, **kw):
            if not req.operator.is_staff:
                from django.http import HttpResponseForbidden

                return HttpResponseForbidden("Staff operators only.")
            return view(req, *a, **kw)

        return inner(request, *args, **kwargs)

    return wrapped
