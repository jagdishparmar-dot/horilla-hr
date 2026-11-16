"""Tenant slug for cache keys, uploads, and scheduled work.

The control database is not a tenant. Callers that have neither an active
tenant alias nor the control-plane scope must stop before they read or write
shared state.
"""

from contextvars import ContextVar, Token

from control.context import get_tenant_alias

_scope: ContextVar[str | None] = ContextVar("horilla_cache_scope", default=None)


def activate_cache_scope(scope: str) -> Token:
    return _scope.set(scope)


def clear_cache_scope(token: Token | None = None) -> None:
    if token is None:
        _scope.set(None)
        return
    _scope.reset(token)


def get_cache_scope() -> str | None:
    return _scope.get()


def active_tenant_slug() -> str | None:
    """Slug for the current tenant, or None on the control plane and when unset."""
    scope = _scope.get()
    if scope and scope != "control":
        return scope
    alias = get_tenant_alias()
    if alias and alias.startswith("tenant_"):
        return alias[len("tenant_") :]
    return None
