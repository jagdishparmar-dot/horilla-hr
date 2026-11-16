"""Tenant slug, database, and role names.

The slug is the customer id. It becomes both the PostgreSQL database name
and the login role name (``tenant_<slug>``). A slug cannot change after that
database exists: renaming is a new tenant plus a restore, not ALTER DATABASE.

This module must not accept, store, or log a tenant database password.
"""

import re

SLUG_PATTERN = re.compile(r"^[a-z][a-z0-9_]{2,30}$")

# Rejected as a slug. These are also illegal database names for a tenant.
RESERVED_SLUGS = frozenset(
    {
        "postgres",
        "template0",
        "template1",
        "horilla_control",
        "default",
        "public",
    }
)


class TenantSlugError(ValueError):
    """The slug cannot be used to name a tenant database."""


def validate_tenant_slug(slug: str) -> str:
    """Return the normalized slug or raise TenantSlugError."""
    if not isinstance(slug, str):
        raise TenantSlugError("Tenant slug must be a string.")
    normalized = slug.strip().lower()
    if not SLUG_PATTERN.fullmatch(normalized):
        raise TenantSlugError(
            "Tenant slug must match ^[a-z][a-z0-9_]{2,30}$ "
            "(3 to 31 characters, starting with a letter)."
        )
    if normalized in RESERVED_SLUGS:
        raise TenantSlugError(f"Tenant slug '{normalized}' is reserved.")
    return normalized


def tenant_database_name(slug: str) -> str:
    return f"tenant_{validate_tenant_slug(slug)}"


def tenant_role_name(slug: str) -> str:
    return tenant_database_name(slug)


def assert_slug_unchanged(existing_slug: str, proposed_slug: str) -> str:
    """Reject a rename. Returns the existing slug when both sides match."""
    current = validate_tenant_slug(existing_slug)
    proposed = validate_tenant_slug(proposed_slug)
    if current != proposed:
        raise TenantSlugError(
            "Tenant slug cannot change after the database exists. "
            "Create a new tenant and restore into it."
        )
    return current
