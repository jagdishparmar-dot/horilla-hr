"""Gate the tenant Initialize Database screen with the provisioned password.

The shared DB_INIT_PASSWORD still unlocks a single-tenant install. A tenant
host accepts only the password stored for that tenant, so a visitor who can
open a fresh host cannot create the admin.

The dashboard shows that password once, in the operator session that just
regenerated it. A later request does not read it back out of the control row.
"""

import hmac
import secrets

from django.conf import settings

from control.crypto import TenantPasswordError
from control.models import Tenant

REVEAL_SESSION_KEY = "control_setup_reveal"


class SetupAccessError(Exception):
    """Regenerate was asked for when no setup password is pending."""


def invite_state(tenant) -> str:
    """Pending, accepted, or not_issued. The password itself is not returned."""
    if tenant.setup_password_encrypted:
        return "pending"
    if tenant.status in (Tenant.Status.ACTIVE, Tenant.Status.TRIALING):
        return "accepted"
    return "not_issued"


def regenerate_setup_password(tenant) -> str:
    """Replace the pending password. The caller shows the return value once."""
    if not tenant.setup_password_encrypted:
        raise SetupAccessError("The setup password has already been cleared.")
    plain = secrets.token_urlsafe(18)
    tenant.set_setup_password(plain)
    tenant.save(update_fields=["setup_password_encrypted"])
    return plain


def stage_setup_password(request, slug, plain) -> None:
    bag = dict(request.session.get(REVEAL_SESSION_KEY) or {})
    bag[slug] = plain
    request.session[REVEAL_SESSION_KEY] = bag


def consume_setup_password(request, slug) -> str:
    bag = dict(request.session.get(REVEAL_SESSION_KEY) or {})
    if slug not in bag:
        return ""
    plain = bag.pop(slug) or ""
    if bag:
        request.session[REVEAL_SESSION_KEY] = bag
    else:
        del request.session[REVEAL_SESSION_KEY]
    return plain


def setup_password_matches(request, submitted: str) -> bool:
    submitted = submitted or ""
    tenant = getattr(request, "tenant", None)
    if not getattr(settings, "HORILLA_MULTITENANT", False) or tenant is None:
        expected = settings.DB_INIT_PASSWORD or ""
        return bool(expected) and hmac.compare_digest(submitted, expected)
    token = getattr(tenant, "setup_password_encrypted", "") or ""
    if not token or not submitted:
        return False
    try:
        expected = tenant.setup_password()
    except TenantPasswordError:
        return False
    return hmac.compare_digest(submitted, expected)


def clear_setup_password(request) -> None:
    tenant = getattr(request, "tenant", None)
    if tenant is None or not getattr(tenant, "setup_password_encrypted", ""):
        return
    tenant.setup_password_encrypted = ""
    tenant.save(update_fields=["setup_password_encrypted"])
