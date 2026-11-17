"""Gate the tenant Initialize Database screen with the provisioned password.

The shared DB_INIT_PASSWORD still unlocks a single-tenant install. A tenant
host accepts only the password stored for that tenant, so a visitor who can
open a fresh host cannot create the admin.
"""

import hmac

from django.conf import settings

from control.crypto import TenantPasswordError


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
