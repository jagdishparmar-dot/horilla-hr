"""Active tenant database alias.

The router reads this. Middleware in a later phase sets it per request and
clears it in a finally block. Background jobs set it around one tenant at a
time. Nothing here may store a database password.
"""

from contextvars import ContextVar, Token

_alias: ContextVar[str | None] = ContextVar("tenant_db_alias", default=None)


def get_tenant_alias() -> str | None:
    return _alias.get()


def activate_tenant_alias(alias: str) -> Token:
    if not alias or alias == "default":
        raise ValueError("Tenant alias must name a tenant database, not default.")
    return _alias.set(alias)


def clear_tenant_alias(token: Token | None = None) -> None:
    if token is None:
        _alias.set(None)
        return
    _alias.reset(token)


def hr_queries_allowed() -> bool:
    """False on the control database while multi-tenant mode is on.

    Startup migrate and post_migrate handlers run there with no tenant
    selected. They must not touch HR tables until a tenant alias is active.
    """
    from django.conf import settings

    if not getattr(settings, "HORILLA_MULTITENANT", False):
        return True
    return bool(get_tenant_alias())
