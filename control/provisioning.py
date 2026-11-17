"""Create, suspend, resume, and delete tenant databases.

The dashboard only inserts a queued ProvisionJob. This module runs that job.
Database passwords are never put in job errors or logs.
"""

import re
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import DatabaseError, connections, transaction
from django.utils import timezone

from control.context import activate_tenant_alias, clear_tenant_alias
from control.crypto import redact_job_error
from control.db import ensure_tenant_connection
from control.models import Domain, ProvisionJob, Tenant
from control.naming import tenant_database_name, tenant_role_name, validate_tenant_slug

PROVISION_STALE_AFTER = timedelta(minutes=30)
IDENT_RE = re.compile(r"^tenant_[a-z][a-z0-9_]{2,30}$")

CREATE_STEPS = (
    "validate",
    "create_role",
    "create_database",
    "revoke_public",
    "grant_connect",
    "revoke_other_roles",
    "store_connection",
    "migrate",
    "seed",
    "activate",
)


class ProvisionError(Exception):
    """A provisioning step failed. The message must not contain a password."""


def enqueue_create(*, name, slug, plan=""):
    """Queue a tenant. The admin is created later on the tenant host.

    A setup password is stored encrypted on the tenant. The operator dashboard
    shows it, and Initialize Database accepts it. No Horilla user is created here.
    """
    slug = validate_tenant_slug(slug)
    tenant = Tenant(
        name=name,
        slug=slug,
        status=Tenant.Status.PROVISIONING,
        plan=plan or "",
    )
    tenant.set_setup_password(secrets.token_urlsafe(18))
    tenant.save()
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.CREATE,
        status=ProvisionJob.Status.QUEUED,
        payload={
            "plan": plan or "",
            "completed_steps": [],
        },
    )


def enqueue_retry(tenant):
    previous = tenant.jobs.order_by("-pk").first()
    payload = dict(previous.payload or {}) if previous else {}
    payload["completed_steps"] = list(payload.get("completed_steps") or [])
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.CREATE,
        status=ProvisionJob.Status.QUEUED,
        payload=payload,
    )


def enqueue_suspend(tenant):
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.SUSPEND,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_resume(tenant):
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.RESUME,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_backup(tenant):
    """Queue a backup. Phase 5 runs pg_dump; this does not open the database."""
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.BACKUP,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_migrate(tenant):
    """Queue a migrate. The worker does not run it until tenant migrate jobs are enabled."""
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.MIGRATE,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_restore(tenant, dump_name):
    """Queue a restore. The dump name is a file name, not a path or a password."""
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,200}", dump_name or ""):
        raise ProvisionError("Dump name is not valid.")
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.RESTORE,
        status=ProvisionJob.Status.QUEUED,
        payload={"dump_name": dump_name},
    )


def enqueue_delete(tenant, confirm_slug):
    if confirm_slug != tenant.slug:
        raise ProvisionError("Slug confirmation does not match.")
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.DELETE,
        status=ProvisionJob.Status.QUEUED,
        payload={"confirm_slug": confirm_slug},
    )


def reclaim_stale_jobs(now=None):
    """Fail jobs left running by a dead worker. The limit is 30 minutes."""
    moment = now or timezone.now()
    cutoff = moment - PROVISION_STALE_AFTER
    stale = list(
        ProvisionJob.objects.filter(
            status=ProvisionJob.Status.RUNNING,
            started_at__lt=cutoff,
        )
    )
    for job in stale:
        job.status = ProvisionJob.Status.FAILED
        job.set_error("Reclaimed after 30 minutes without a finish.")
        job.finished_at = moment
        job.save(update_fields=["status", "error", "finished_at"])
        tenant = job.tenant
        if tenant.status in (Tenant.Status.PROVISIONING, Tenant.Status.DELETING):
            tenant.status = Tenant.Status.FAILED
            tenant.save(update_fields=["status"])
    return len(stale)


def process_available_jobs():
    """Run queued jobs one at a time. Returns how many were processed."""
    processed = 0
    while True:
        job_id = _claim_next_job()
        if job_id is None:
            return processed
        job = ProvisionJob.objects.select_related("tenant").get(pk=job_id)
        _run_claimed(job)
        processed += 1


def maintenance_cursor():
    """Autocommit cursor on the maintenance database. CREATE DATABASE needs it."""
    return connections["default"].creation._nodb_cursor()


def quote_ident(name: str) -> str:
    if not IDENT_RE.fullmatch(name or ""):
        raise ProvisionError("Unsafe database identifier.")
    return '"' + name + '"'


def run_create(job):
    payload = dict(job.payload or {})
    completed = list(payload.get("completed_steps") or [])
    handlers = {
        "validate": _step_validate,
        "create_role": _step_create_role,
        "create_database": _step_create_database,
        "revoke_public": _step_revoke_public,
        "grant_connect": _step_grant_connect,
        "revoke_other_roles": _step_revoke_other_roles,
        "store_connection": _step_store_connection,
        "migrate": _step_migrate,
        "seed": _step_seed,
        "activate": _step_activate,
    }
    for step in CREATE_STEPS:
        if step in completed:
            continue
        job.step = step
        job.save(update_fields=["step"])
        handlers[step](job)
        completed.append(step)
        payload["completed_steps"] = completed
        job.payload = payload
        job.save(update_fields=["payload"])
    _succeed(job)


def suspend_tenant(tenant):
    tenant.status = Tenant.Status.SUSPENDED
    tenant.save(update_fields=["status"])


def resume_tenant(tenant):
    if not _database_exists(tenant.db_name):
        raise ProvisionError("Tenant database is missing.")
    tenant.status = Tenant.Status.ACTIVE
    tenant.save(update_fields=["status"])


def dump_tenant(tenant) -> str:
    """Dump the tenant database before a delete. The path is backups/<slug>/."""
    from control.backup import dump_tenant_database

    return dump_tenant_database(tenant)


def _run_restore(job):
    """Suspend, load the dump from this tenant's folder, then mark active."""
    from control.backup import restore_tenant_database

    tenant = job.tenant
    tenant.status = Tenant.Status.SUSPENDED
    tenant.save(update_fields=["status"])
    job.step = "restore"
    job.save(update_fields=["step"])
    restore_tenant_database(tenant, (job.payload or {}).get("dump_name") or "")
    tenant.status = Tenant.Status.ACTIVE
    tenant.save(update_fields=["status"])


def delete_tenant(job, dump=None):
    tenant = job.tenant
    confirm = (job.payload or {}).get("confirm_slug")
    if confirm != tenant.slug:
        raise ProvisionError("Slug confirmation does not match.")
    tenant.status = Tenant.Status.DELETING
    tenant.save(update_fields=["status"])
    job.step = "dump"
    job.save(update_fields=["step"])
    dumper = dump if dump is not None else dump_tenant
    dumper(tenant)
    job.step = "drop"
    job.save(update_fields=["step"])
    _drop_database_and_role(tenant)
    tenant.domains.all().delete()
    tenant.status = Tenant.Status.DELETED
    tenant.deleted_at = timezone.now()
    tenant.save(update_fields=["status", "deleted_at"])


def migrate_tenant(tenant):
    from django.core.management import call_command

    alias = ensure_tenant_connection(tenant)
    token = activate_tenant_alias(alias)
    try:
        call_command("migrate", database=alias, interactive=False, verbosity=1)
    finally:
        clear_tenant_alias(token)


def seed_tenant(tenant, payload):
    """Leave the tenant database without a login.

    The first admin and company are created from the tenant's Initialize
    Database screen, after the setup password is entered.
    """
    return None


def _claim_next_job():
    with transaction.atomic():
        job = (
            ProvisionJob.objects.select_for_update(skip_locked=True)
            .filter(status=ProvisionJob.Status.QUEUED)
            .order_by("pk")
            .first()
        )
        if job is None:
            return None
        job.status = ProvisionJob.Status.RUNNING
        job.started_at = timezone.now()
        job.save(update_fields=["status", "started_at"])
        return job.pk


def _run_claimed(job):
    try:
        if job.kind == ProvisionJob.Kind.CREATE:
            run_create(job)
        elif job.kind == ProvisionJob.Kind.SUSPEND:
            job.step = "suspend"
            suspend_tenant(job.tenant)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.RESUME:
            job.step = "resume"
            resume_tenant(job.tenant)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.DELETE:
            delete_tenant(job)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.BACKUP:
            job.step = "dump"
            job.save(update_fields=["step"])
            path = dump_tenant(job.tenant)
            payload = dict(job.payload or {})
            payload["dump_path"] = path
            job.payload = payload
            job.save(update_fields=["payload"])
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.MIGRATE:
            job.step = "migrate"
            migrate_tenant(job.tenant)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.RESTORE:
            _run_restore(job)
            _succeed(job)
        else:
            raise ProvisionError("Unsupported provisioning job.")
    except Exception as exc:
        _fail(job, exc)


def _succeed(job):
    job.status = ProvisionJob.Status.SUCCEEDED
    job.finished_at = timezone.now()
    job.save(update_fields=["status", "finished_at", "step"])


def _fail(job, exc):
    job.status = ProvisionJob.Status.FAILED
    if isinstance(exc, ProvisionError):
        job.set_error(str(exc))
    elif isinstance(exc, DatabaseError):
        job.set_error(redact_job_error(str(exc)))
    else:
        job.set_error(type(exc).__name__)
    job.finished_at = timezone.now()
    job.save(update_fields=["status", "error", "finished_at", "step"])
    tenant = job.tenant
    tenant.refresh_from_db()
    if tenant.status in (Tenant.Status.PROVISIONING, Tenant.Status.DELETING):
        tenant.status = Tenant.Status.FAILED
        tenant.save(update_fields=["status"])


def _step_validate(job):
    validate_tenant_slug(job.tenant.slug)


def _step_create_role(job):
    tenant = job.tenant
    if not tenant.db_password_encrypted:
        tenant.set_db_password(secrets.token_urlsafe(24))
        tenant.save(update_fields=["db_password_encrypted"])
    role = tenant_role_name(tenant.slug)
    with maintenance_cursor() as cursor:
        if _exists(cursor, "SELECT 1 FROM pg_roles WHERE rolname = %s", [role]):
            return
        password = tenant.db_password()
        cursor.execute(
            f"CREATE ROLE {quote_ident(role)} LOGIN PASSWORD '{_quote_literal(password)}'"
        )


def _step_create_database(job):
    tenant = job.tenant
    name = tenant_database_name(tenant.slug)
    role = tenant_role_name(tenant.slug)
    with maintenance_cursor() as cursor:
        if _exists(cursor, "SELECT 1 FROM pg_database WHERE datname = %s", [name]):
            return
        cursor.execute(
            f"CREATE DATABASE {quote_ident(name)} OWNER {quote_ident(role)}"
        )


def _step_revoke_public(job):
    name = quote_ident(tenant_database_name(job.tenant.slug))
    with maintenance_cursor() as cursor:
        cursor.execute(f"REVOKE ALL ON DATABASE {name} FROM PUBLIC")


def _step_grant_connect(job):
    name = quote_ident(tenant_database_name(job.tenant.slug))
    role = quote_ident(tenant_role_name(job.tenant.slug))
    with maintenance_cursor() as cursor:
        cursor.execute(f"GRANT CONNECT ON DATABASE {name} TO {role}")


def _step_revoke_other_roles(job):
    name = tenant_database_name(job.tenant.slug)
    role = tenant_role_name(job.tenant.slug)
    with maintenance_cursor() as cursor:
        cursor.execute(
            "SELECT rolname FROM pg_roles WHERE rolname LIKE %s ESCAPE %s AND rolname <> %s",
            [r"tenant\_%", "\\", role],
        )
        others = [row[0] for row in cursor.fetchall()]
        quoted_db = quote_ident(name)
        for other in others:
            cursor.execute(
                f"REVOKE CONNECT ON DATABASE {quoted_db} FROM {quote_ident(other)}"
            )


def _step_store_connection(job):
    tenant = job.tenant
    default = connections["default"].settings_dict
    tenant.db_name = tenant_database_name(tenant.slug)
    tenant.db_user = tenant_role_name(tenant.slug)
    tenant.db_host = default.get("HOST") or tenant.db_host or "db"
    tenant.db_port = int(default.get("PORT") or tenant.db_port or 5432)
    tenant.save(update_fields=["db_name", "db_user", "db_host", "db_port"])


def _step_migrate(job):
    migrate_tenant(job.tenant)


def _step_seed(job):
    seed_tenant(job.tenant, job.payload or {})


def _step_activate(job):
    tenant = job.tenant
    host = f"{tenant.slug}.{settings.HORILLA_PLATFORM_DOMAIN}"
    Domain.objects.update_or_create(
        host=host,
        defaults={"tenant": tenant, "is_primary": True, "verified": True},
    )
    tenant.status = Tenant.Status.ACTIVE
    tenant.activated_at = timezone.now()
    tenant.save(update_fields=["status", "activated_at"])


def _database_exists(name: str) -> bool:
    if not name:
        return False
    with maintenance_cursor() as cursor:
        return _exists(cursor, "SELECT 1 FROM pg_database WHERE datname = %s", [name])


def _exists(cursor, sql, params) -> bool:
    cursor.execute(sql, params)
    return cursor.fetchone() is not None


def _quote_literal(value: str) -> str:
    return value.replace("'", "''")


def _drop_database_and_role(tenant):
    name = quote_ident(tenant.db_name or tenant_database_name(tenant.slug))
    role = quote_ident(tenant.db_user or tenant_role_name(tenant.slug))
    with maintenance_cursor() as cursor:
        cursor.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
        cursor.execute(f"DROP ROLE IF EXISTS {role}")
