"""S3-compatible object store for tenant database dumps.

Configured by ``BACKUP_S3_*`` environment variables, read at the moment of
use (like ``TENANT_DB_FERNET_KEY``). When ``BACKUP_S3_BUCKET`` is unset the
store is off and dumps stay on the local backups volume.

Keys mirror the local layout: ``[<prefix>/]backups/<slug>/<timestamp>.dump``.
Every function validates the slug and the dump name before it builds a key,
so one tenant's restore cannot name another tenant's object.

Secrets are never logged, never stored in the control database, and never
put into an exception message: a failed boto3 call is re-raised as
``BackupStoreError`` carrying the exception type name only.
"""

import os
import re
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

from control.naming import validate_tenant_slug

BUCKET_ENV = "BACKUP_S3_BUCKET"
ENDPOINT_ENV = "BACKUP_S3_ENDPOINT_URL"
ACCESS_KEY_ENV = "BACKUP_S3_ACCESS_KEY"
SECRET_KEY_ENV = "BACKUP_S3_SECRET_KEY"
REGION_ENV = "BACKUP_S3_REGION"
PREFIX_ENV = "BACKUP_S3_PREFIX"
KEEP_DAILY_ENV = "BACKUP_KEEP_DAILY"
KEEP_WEEKLY_ENV = "BACKUP_KEEP_WEEKLY"

DEFAULT_KEEP_DAILY = 7
DEFAULT_KEEP_WEEKLY = 4

DUMP_NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,200}\.dump$")

# Codes head_object returns for "no such object" across S3-compatible stores.
_MISSING_CODES = {"404", "NoSuchKey", "NotFound"}


class BackupStoreError(Exception):
    """An object-store operation failed. The message holds no secret."""


class BackupStoreNotConfigured(BackupStoreError):
    """BACKUP_S3_BUCKET is not set. Callers fall back to the local folder."""


def configured() -> bool:
    return bool(os.environ.get(BUCKET_ENV, "").strip())


def keep_daily() -> int:
    return max(1, int(os.environ.get(KEEP_DAILY_ENV, "").strip() or DEFAULT_KEEP_DAILY))


def keep_weekly() -> int:
    return max(0, int(os.environ.get(KEEP_WEEKLY_ENV, "").strip() or DEFAULT_KEEP_WEEKLY))


def _bucket() -> str:
    bucket = os.environ.get(BUCKET_ENV, "").strip()
    if not bucket:
        raise BackupStoreNotConfigured("BACKUP_S3_BUCKET is not set.")
    return bucket


def _prefix() -> str:
    prefix = (os.environ.get(PREFIX_ENV, "") or "").strip().strip("/")
    return f"{prefix}/" if prefix else ""


def validate_dump_name(name: str) -> str:
    """A bare ``*.dump`` file name. Paths and separators are refused."""
    if (
        not name
        or not DUMP_NAME_RE.fullmatch(name)
        or name != Path(name).name
        or name.startswith(".")
    ):
        raise BackupStoreError("Dump name is not valid.")
    return name


def object_key(slug: str, name: str) -> str:
    """The only key this slug may read or write for this dump name."""
    return f"{slug_prefix(slug)}{validate_dump_name(name)}"


def slug_prefix(slug: str) -> str:
    return f"{_prefix()}backups/{validate_tenant_slug(slug)}/"


def _client():
    """A boto3 S3 client from the environment. Never cached into settings."""
    _bucket()  # raises BackupStoreNotConfigured when the store is off
    access = os.environ.get(ACCESS_KEY_ENV, "").strip()
    secret = os.environ.get(SECRET_KEY_ENV, "").strip()
    if not access or not secret:
        raise ImproperlyConfigured(
            "BACKUP_S3_ACCESS_KEY and BACKUP_S3_SECRET_KEY are required when "
            "BACKUP_S3_BUCKET is set."
        )
    import boto3

    endpoint = os.environ.get(ENDPOINT_ENV, "").strip()
    region = os.environ.get(REGION_ENV, "").strip() or "auto"
    return boto3.client(
        "s3",
        endpoint_url=endpoint or None,
        aws_access_key_id=access,
        aws_secret_access_key=secret,
        region_name=region,
    )


def _wrap(action: str, exc: Exception) -> BackupStoreError:
    """Secret-free error. boto3 messages can include endpoint URLs; drop them."""
    if isinstance(exc, (BackupStoreError, ImproperlyConfigured)):
        return exc
    return BackupStoreError(f"Backup store {action} failed: {type(exc).__name__}")


def _missing(exc: Exception) -> bool:
    error = getattr(exc, "response", None) or {}
    code = str((error.get("Error") or {}).get("Code", ""))
    return code in _MISSING_CODES


def put(local_path, slug: str, name: str) -> dict:
    """Upload one dump. Returns ``{"key", "size"}``."""
    key = object_key(slug, name)
    size = Path(local_path).stat().st_size
    client = _client()
    try:
        client.upload_file(str(local_path), _bucket(), key)
    except Exception as exc:  # noqa: BLE001 - re-raised without secrets
        raise _wrap("upload", exc) from exc
    return {"key": key, "size": size}


def get(slug: str, name: str, local_path) -> None:
    """Download one dump of this slug to ``local_path``."""
    key = object_key(slug, name)
    client = _client()
    try:
        client.download_file(_bucket(), key, str(local_path))
    except Exception as exc:  # noqa: BLE001
        raise _wrap("download", exc) from exc


def head(slug: str, name: str) -> dict | None:
    """``{"key", "size", "last_modified"}`` or None when the object is absent."""
    key = object_key(slug, name)
    client = _client()
    try:
        response = client.head_object(Bucket=_bucket(), Key=key)
    except Exception as exc:  # noqa: BLE001
        if _missing(exc):
            return None
        raise _wrap("head", exc) from exc
    return {
        "key": key,
        "size": int(response.get("ContentLength") or 0),
        "last_modified": response.get("LastModified"),
    }


def list_keys(slug: str) -> list[dict]:
    """This slug's dumps, newest name first: ``{"name", "size", "last_modified"}``."""
    prefix = slug_prefix(slug)
    client = _client()
    entries = []
    token = None
    while True:
        kwargs = {"Bucket": _bucket(), "Prefix": prefix}
        if token:
            kwargs["ContinuationToken"] = token
        try:
            response = client.list_objects_v2(**kwargs)
        except Exception as exc:  # noqa: BLE001
            raise _wrap("list", exc) from exc
        for item in response.get("Contents") or []:
            name = str(item.get("Key", "")).rsplit("/", 1)[-1]
            if not DUMP_NAME_RE.fullmatch(name) or name.startswith("."):
                continue
            entries.append(
                {
                    "name": name,
                    "size": int(item.get("Size") or 0),
                    "last_modified": item.get("LastModified"),
                }
            )
        if not response.get("IsTruncated"):
            break
        token = response.get("NextContinuationToken")
        if not token:
            break
    entries.sort(key=lambda entry: entry["name"], reverse=True)
    return entries


def delete(slug: str, name: str) -> None:
    key = object_key(slug, name)
    client = _client()
    try:
        client.delete_object(Bucket=_bucket(), Key=key)
    except Exception as exc:  # noqa: BLE001
        raise _wrap("delete", exc) from exc
