"""Presence check for the tenant database password key.

The key itself is read from the environment at the moment of use. It is not
copied into Django settings, logs, job output, or the media volume.
"""

import os

from django.core.exceptions import ImproperlyConfigured

TENANT_DB_FERNET_KEY_ENV = "TENANT_DB_FERNET_KEY"
MULTITENANT_ENV = "HORILLA_MULTITENANT"

_TRUE = {"1", "true", "yes", "on"}


def multitenant_enabled(environ=None) -> bool:
    source = os.environ if environ is None else environ
    return source.get(MULTITENANT_ENV, "").strip().lower() in _TRUE


def tenant_db_fernet_key(environ=None) -> str:
    """Return the Fernet key. Raise when multitenant mode is on and it is missing.

    An empty string is returned when multitenant mode is off, so a
    single-tenant deployment does not need the key yet.
    """
    source = os.environ if environ is None else environ
    key = source.get(TENANT_DB_FERNET_KEY_ENV, "").strip()
    if multitenant_enabled(source) and not key:
        raise ImproperlyConfigured(
            "TENANT_DB_FERNET_KEY is required when HORILLA_MULTITENANT is "
            "enabled. Generate one with: python -c "
            '"from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"'
        )
    return key
