"""Open a PostgreSQL alias for one tenant. Does not log the password."""

import copy
import threading

from django.conf import settings
from django.db import connections

from control.crypto import decrypt_tenant_password
from control.naming import tenant_database_name

_lock = threading.Lock()


def _runtime_databases():
    """The connection map, detached from django.conf.settings.DATABASES.

    ConnectionHandler.settings is that settings dict. Writing an alias into
    it would put the tenant password where a debug page can print it.
    """
    from django.conf import settings as django_settings

    current = connections.settings
    if current is django_settings.DATABASES:
        current = current.copy()
        connections.__dict__["settings"] = current
    return current


def ensure_tenant_connection(tenant) -> str:
    """Register ``tenant_<slug>`` on the connection handler and return the alias."""
    alias = tenant_database_name(tenant.slug)
    password = decrypt_tenant_password(tenant.db_password_encrypted)
    with _lock:
        databases = _runtime_databases()
        current = databases.get(alias)
        if (
            current
            and current.get("PASSWORD") == password
            and current.get("NAME") == tenant.db_name
        ):
            return alias
        config = copy.deepcopy(databases["default"])
        config.update(
            {
                "ENGINE": "django.db.backends.postgresql",
                "NAME": tenant.db_name,
                "USER": tenant.db_user,
                "PASSWORD": password,
                "HOST": tenant.db_host,
                "PORT": str(tenant.db_port),
                "CONN_MAX_AGE": settings.TENANT_CONN_MAX_AGE,
                "CONN_HEALTH_CHECKS": True,
                "ATOMIC_REQUESTS": False,
                "AUTOCOMMIT": True,
                "TIME_ZONE": None,
                "OPTIONS": {"connect_timeout": 5},
            }
        )
        config["TEST"] = {
            "CHARSET": None,
            "COLLATION": None,
            "MIGRATE": True,
            "MIRROR": None,
            "NAME": None,
        }
        databases[alias] = config
        if alias in connections:
            connections[alias].close()
    return alias
