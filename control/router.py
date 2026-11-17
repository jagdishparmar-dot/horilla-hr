"""Route the control plane to ``default`` and customer data to a tenant alias.

Strict routing runs only when ``HORILLA_MULTITENANT`` is on. Until then every
app stays on the current database, so the single-tenant stack keeps working.
"""

from django.conf import settings

from control.context import get_tenant_alias

# Tables that belong only in the control database. HorillaUser is
# ``horilla_auth`` and is intentionally absent: each tenant database has its
# own users. ``django_apscheduler`` stays here because the single scheduler
# records jobs in the control database. Sessions stay here too; the host-only
# cookie is what keeps one tenant's session off another host.
CONTROL_APP_LABELS = frozenset(
    {
        "control",
        "sessions",
        "django_apscheduler",
    }
)

# These apps are created in the control database and in every tenant database.
# HorillaUser's groups and permissions reference auth_group, so a tenant
# migrate that only records the auth migrations leaves that table missing.
TENANT_SCHEMA_APP_LABELS = frozenset({"auth", "contenttypes"})


class TenantRoutingError(RuntimeError):
    """An HR query ran without a tenant database selected."""


def _multitenant() -> bool:
    return bool(getattr(settings, "HORILLA_MULTITENANT", False))


def _tenant_alias_name(db: str) -> bool:
    return db.startswith("tenant_")


class TenantRouter:
    def db_for_read(self, model, **hints):
        return self._route(model._meta.app_label)

    def db_for_write(self, model, **hints):
        return self._route(model._meta.app_label)

    def allow_relation(self, obj1, obj2, **hints):
        if not _multitenant():
            return None
        return obj1._state.db == obj2._state.db

    def allow_migrate(self, db, app_label, model_name=None, **hints):
        if not _multitenant():
            return None
        if app_label in TENANT_SCHEMA_APP_LABELS:
            return db == "default" or _tenant_alias_name(db)
        if app_label in CONTROL_APP_LABELS:
            return db == "default"
        return _tenant_alias_name(db)

    def _route(self, app_label: str):
        if not _multitenant():
            return None
        if app_label in TENANT_SCHEMA_APP_LABELS:
            return get_tenant_alias() or "default"
        if app_label in CONTROL_APP_LABELS:
            return "default"
        alias = get_tenant_alias()
        if not alias:
            raise TenantRoutingError(
                f"Refusing to query '{app_label}' without a tenant database."
            )
        return alias
