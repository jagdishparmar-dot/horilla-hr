"""Encrypt tenant database passwords.

The Fernet key is read from the environment at the moment of use. Ciphertext
and plaintext are not logged. Callers must not put either value on a model
``__str__``.
"""

import os
import re

from cryptography.fernet import Fernet, InvalidToken
from django.core.exceptions import ImproperlyConfigured

from control.secrets import TENANT_DB_FERNET_KEY_ENV

_SECRET_ASSIGNMENT = re.compile(
    r"(?i)\b(password|secret|token|fernet)\b(\s*[=:]\s*)(\S+)"
)


class TenantPasswordError(ImproperlyConfigured):
    """A tenant database password could not be stored or read."""


def _fernet() -> Fernet:
    key = os.environ.get(TENANT_DB_FERNET_KEY_ENV, "").strip()
    if not key:
        raise ImproperlyConfigured(
            "TENANT_DB_FERNET_KEY is required to encrypt a tenant database "
            "password."
        )
    try:
        return Fernet(key.encode())
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(
            "TENANT_DB_FERNET_KEY is not a valid Fernet key."
        ) from exc


def encrypt_tenant_password(plain: str) -> str:
    if not isinstance(plain, str) or plain == "":
        raise TenantPasswordError("Tenant database password must be a non-empty string.")
    return _fernet().encrypt(plain.encode()).decode()


def decrypt_tenant_password(token: str) -> str:
    if not token:
        raise TenantPasswordError("Tenant database password is not set.")
    try:
        return _fernet().decrypt(token.encode()).decode()
    except InvalidToken as exc:
        raise TenantPasswordError(
            "Tenant database password could not be decrypted."
        ) from exc


def redact_job_error(message: str, limit: int = 2000) -> str:
    """Drop secret assignments and cap length before a job row stores the text."""
    text = _SECRET_ASSIGNMENT.sub(r"\1\2[redacted]", message or "")
    if len(text) > limit:
        return text[:limit]
    return text
