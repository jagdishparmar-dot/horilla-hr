"""Create, suspend, resume, and delete tenant databases.

The dashboard only inserts a queued ProvisionJob. This module runs that job.
Database passwords are never put in job errors or logs.
"""

import logging
import re
import secrets
from datetime import timedelta

from django.conf import settings
from django.db import DatabaseError, connections, transaction
from django.utils import timezone

from control import backup_store
from control.context import activate_tenant_alias, clear_tenant_alias
from control.crypto import redact_job_error
from control.db import ensure_tenant_connection
from control.catalog import UNASSIGNED
from control.models import Domain, Invoice, Plan, ProvisionJob, Tenant
from control.naming import tenant_database_name, tenant_role_name, validate_tenant_slug

logger = logging.getLogger(__name__)

PROVISION_STALE_AFTER = timedelta(minutes=30)
IDENT_RE = re.compile(r"^tenant_[a-z][a-z0-9_]{2,30}$")
CATALOG_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]{0,62}$")

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


def _resolve_plan(plan):
    if isinstance(plan, Plan):
        return plan
    code = (plan or "").strip().lower()
    if not code:
        code = UNASSIGNED
    found = Plan.objects.filter(code=code).first()
    if found is None:
        raise ProvisionError(f"Unknown plan '{code}'.")
    return found


TRIAL_DAYS = 14


def enqueue_create(
    *,
    name,
    slug,
    plan="",
    cadence=Tenant.Cadence.MONTHLY,
    seats=None,
    addons=None,
    modules=None,
    industry="",
    admin_name="",
    admin_email="",
    start_as_trial=False,
):
    """Queue a tenant. The admin is created later on the tenant host.

    A setup password is stored encrypted on the tenant. The operator dashboard
    shows it, and Initialize Database accepts it. No Horilla user is created here.
    ``seat_limit`` is copied from ``seats``. Storage is that count times the plan's GB per seat.
    Module flags are stored only. They do not install or remove Horilla apps.
    """
    slug = validate_tenant_slug(slug)
    chosen = _resolve_plan(plan)
    if cadence not in {
        Tenant.Cadence.MONTHLY,
        Tenant.Cadence.SEMIANNUAL,
        Tenant.Cadence.ANNUAL,
    }:
        raise ProvisionError("Unknown billing cadence.")
    seat_count = int(seats) if seats is not None else (chosen.seat_cap or 25)
    if seat_count < 1:
        raise ProvisionError("Seat count must be at least 1.")
    if chosen.seat_cap is not None and seat_count > chosen.seat_cap:
        raise ProvisionError(f"{chosen.name} allows up to {chosen.seat_cap} seats.")
    per_seat = chosen.storage_gb_per_seat or 0
    selected = list(addons or [])
    flags = modules or {}
    tenant = Tenant(
        name=name,
        slug=slug,
        status=Tenant.Status.PROVISIONING,
        plan_fk=chosen,
        cadence=cadence,
        seat_limit=seat_count,
        storage_limit_gb=seat_count * per_seat,
        module_employee_records=bool(flags.get("employee_records", True)),
        module_payroll_engine=bool(flags.get("payroll_engine", True)),
        module_performance_reviews=bool(flags.get("performance_reviews", True)),
        industry=(industry or "").strip(),
        admin_name=(admin_name or "").strip(),
        admin_email=(admin_email or "").strip().lower(),
    )
    tenant.set_setup_password(secrets.token_urlsafe(18))
    tenant.save()
    if selected:
        tenant.addons.set(selected)
    from control.pricing import lock_subscription

    lock_subscription(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.CREATE,
        status=ProvisionJob.Status.QUEUED,
        payload={
            "plan": chosen.code,
            "cadence": cadence,
            "seats": seat_count,
            "addon_codes": [addon.code for addon in selected],
            "start_as_trial": bool(start_as_trial),
            "completed_steps": [],
        },
    )


def enqueue_retry(tenant):
    """Queue another create that continues from completed_steps.

    Only a failed tenant can be retried, and not while a create, delete, or
    removal is already queued. The tenant goes back to provisioning.
    """
    tenant.refresh_from_db()
    if tenant.status != Tenant.Status.FAILED:
        raise ProvisionError("Only a failed tenant can be retried.")
    _reject_if_create_or_delete_blocked(tenant)
    previous = tenant.jobs.order_by("-pk").first()
    payload = dict(previous.payload or {}) if previous else {}
    payload["completed_steps"] = list(payload.get("completed_steps") or [])
    tenant.status = Tenant.Status.PROVISIONING
    tenant.save(update_fields=["status"])
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.CREATE,
        status=ProvisionJob.Status.QUEUED,
        payload=payload,
    )


def _reject_if_create_or_delete_blocked(tenant):
    """Block work that would race a create or delete, or touch a removed tenant.

    A queued suspend, backup, or migrate does not block the others.
    Status is read from the database, not from a stale in-memory copy.
    """
    tenant.refresh_from_db()
    if tenant.status == Tenant.Status.DELETED:
        raise ProvisionError("Tenant is already deleted.")
    if tenant.status == Tenant.Status.DELETING:
        raise ProvisionError("Tenant is already being deleted.")
    if tenant.jobs.filter(
        kind__in=(
            ProvisionJob.Kind.CREATE,
            ProvisionJob.Kind.DELETE,
            ProvisionJob.Kind.PURGE,
        ),
        status__in=(ProvisionJob.Status.QUEUED, ProvisionJob.Status.RUNNING),
    ).exists():
        raise ProvisionError("A create, delete, or removal job is already queued for this tenant.")


def enqueue_suspend(tenant, reason=""):
    tenant.refresh_from_db()
    if tenant.status == Tenant.Status.SUSPENDED:
        raise ProvisionError("Tenant is already suspended.")
    if tenant.status == Tenant.Status.PROVISIONING:
        raise ProvisionError("Tenant is still provisioning.")
    _reject_if_create_or_delete_blocked(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.SUSPEND,
        status=ProvisionJob.Status.QUEUED,
        payload={"suspension_reason": (reason or "").strip()},
    )


def enqueue_resume(tenant):
    _reject_if_create_or_delete_blocked(tenant)
    if tenant.status != Tenant.Status.SUSPENDED:
        raise ProvisionError("Only a suspended tenant can be resumed.")
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.RESUME,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_backup(tenant):
    """Queue a backup. Phase 5 runs pg_dump; this does not open the database."""
    _reject_if_create_or_delete_blocked(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.BACKUP,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_migrate(tenant):
    """Queue a migrate. The worker does not run it until tenant migrate jobs are enabled."""
    _reject_if_create_or_delete_blocked(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.MIGRATE,
        status=ProvisionJob.Status.QUEUED,
    )


def enqueue_restore(tenant, dump_name):
    """Queue a restore. The dump name is a file name, not a path or a password."""
    _reject_if_create_or_delete_blocked(tenant)
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
    _reject_if_create_or_delete_blocked(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.DELETE,
        status=ProvisionJob.Status.QUEUED,
        payload={"confirm_slug": confirm_slug},
    )


def _reject_purge_with_invoices(tenant):
    if tenant.invoices.exists():
        raise ProvisionError(
            "Void or resolve this tenant's invoices before removing the record."
        )


# A live workspace still uses the dump-then-drop delete. Removal is for a
# tenant whose database login cannot be used.
PURGEABLE_STATUSES = (
    Tenant.Status.FAILED,
    Tenant.Status.PROVISIONING,
    Tenant.Status.DELETING,
    Tenant.Status.DELETED,
)


def enqueue_purge(tenant, confirm_slug):
    """Queue a removal that does not dump. The maintenance login drops the database and role."""
    if confirm_slug != tenant.slug:
        raise ProvisionError("Slug confirmation does not match.")
    tenant.refresh_from_db()
    if tenant.status not in PURGEABLE_STATUSES:
        raise ProvisionError(
            "Only a failed or unfinished tenant can be removed without a backup."
        )
    if tenant.jobs.filter(
        kind__in=(
            ProvisionJob.Kind.CREATE,
            ProvisionJob.Kind.DELETE,
            ProvisionJob.Kind.PURGE,
        ),
        status__in=(ProvisionJob.Status.QUEUED, ProvisionJob.Status.RUNNING),
    ).exists():
        raise ProvisionError("A create, delete, or removal job is already queued for this tenant.")
    _reject_purge_with_invoices(tenant)
    return ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.PURGE,
        status=ProvisionJob.Status.QUEUED,
        payload={"confirm_slug": confirm_slug},
    )


def requeue_interrupted_jobs():
    """Put jobs left running by a dead provisioner back on the queue.

    A restart is not a failure. The tenant stays provisioning or deleting.
    Steps already listed in ``completed_steps`` are skipped, and migrate
    continues from the tenant's ``django_migrations`` table.
    """
    return ProvisionJob.objects.filter(status=ProvisionJob.Status.RUNNING).update(
        status=ProvisionJob.Status.QUEUED,
        started_at=None,
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


def quote_catalog_ident(name: str) -> str:
    if not CATALOG_IDENT_RE.fullmatch(name or ""):
        raise ProvisionError("Unsafe database identifier.")
    return '"' + name + '"'


def lock_control_connect():
    """Stop tenant logins from opening the control database.

    PostgreSQL grants CONNECT to PUBLIC. A tenant role is a member of PUBLIC,
    so it can open the control database until that grant is removed. The
    control login keeps CONNECT. Runs only while multi-tenant mode is on, and
    uses an autocommit cursor so the revoke is visible to the next connection.
    """
    if not getattr(settings, "HORILLA_MULTITENANT", False):
        return
    db = settings.DATABASES["default"]
    quoted_db = quote_catalog_ident(db["NAME"])
    quoted_user = quote_catalog_ident(db["USER"])
    with maintenance_cursor() as cursor:
        cursor.execute(f"REVOKE CONNECT ON DATABASE {quoted_db} FROM PUBLIC")
        cursor.execute(f"GRANT CONNECT ON DATABASE {quoted_db} TO {quoted_user}")
        cursor.execute(
            "SELECT rolname FROM pg_roles WHERE rolname LIKE %s ESCAPE %s",
            [r"tenant\_%", "\\"],
        )
        for (role,) in cursor.fetchall():
            if not CATALOG_IDENT_RE.fullmatch(role):
                continue
            cursor.execute(
                f"REVOKE CONNECT ON DATABASE {quoted_db} FROM {quote_catalog_ident(role)}"
            )


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


def suspend_tenant(tenant, reason=""):
    tenant.status = Tenant.Status.SUSPENDED
    tenant.suspension_reason = (reason or "").strip()[:200]
    tenant.save(update_fields=["status", "suspension_reason"])


def _status_after_resume(tenant):
    """Status a suspended tenant returns to. A live trial wins, then an overdue bill."""
    if tenant.trial_ends_at and tenant.trial_ends_at > timezone.now():
        return Tenant.Status.TRIALING
    if tenant.invoices.filter(status=Invoice.Status.PAST_DUE).exists():
        return Tenant.Status.PAST_DUE
    return Tenant.Status.ACTIVE


def resume_tenant(tenant):
    if not _database_exists(tenant.db_name):
        raise ProvisionError("Tenant database is missing.")
    tenant.status = _status_after_resume(tenant)
    tenant.suspension_reason = ""
    tenant.save(update_fields=["status", "suspension_reason"])


def dump_tenant(tenant) -> str:
    """Dump the tenant database before a delete. The path is backups/<slug>/."""
    from control.backup import dump_tenant_database

    return dump_tenant_database(tenant)


def _status_after_restore(tenant, status_before):
    if status_before in (
        Tenant.Status.ACTIVE,
        Tenant.Status.TRIALING,
        Tenant.Status.PAST_DUE,
    ):
        return status_before
    return _status_after_resume(tenant)


def terminate_tenant_sessions(tenant) -> None:
    """Drop other backends on this tenant database. Never the control database.

    The maintenance connection itself is on the control database, so
    ``pid <> pg_backend_pid()`` is a second guard rather than the only one.
    """
    name = (tenant.db_name or "").strip()
    control_name = settings.DATABASES["default"]["NAME"]
    if not name or name == control_name:
        return
    with maintenance_cursor() as cursor:
        cursor.execute(
            "SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
            "WHERE datname = %s AND pid <> pg_backend_pid()",
            [name],
        )


def _run_restore(job):
    """Hold the workspace offline, load the dump, then restore the prior status."""
    from control.backup import restore_tenant_database

    tenant = job.tenant
    payload = dict(job.payload or {})
    if "status_before" not in payload:
        payload["status_before"] = tenant.status
        job.payload = payload
        job.save(update_fields=["payload"])
    tenant.status = Tenant.Status.SUSPENDED
    tenant.save(update_fields=["status"])
    job.step = "terminate"
    job.save(update_fields=["step"])
    terminate_tenant_sessions(tenant)
    job.step = "restore"
    job.save(update_fields=["step"])
    try:
        restore_tenant_database(tenant, payload.get("dump_name") or "")
    except Exception:
        tenant.status = Tenant.Status.SUSPENDED
        tenant.suspension_reason = "Restore failed; workspace held offline."[:200]
        tenant.save(update_fields=["status", "suspension_reason"])
        raise
    tenant.status = _status_after_restore(tenant, payload.get("status_before"))
    tenant.suspension_reason = ""
    tenant.save(update_fields=["status", "suspension_reason"])
    ProvisionJob.objects.create(
        tenant=tenant,
        kind=ProvisionJob.Kind.MIGRATE,
        status=ProvisionJob.Status.QUEUED,
    )


def delete_tenant(job, dump=None):
    tenant = job.tenant
    confirm = (job.payload or {}).get("confirm_slug")
    if confirm != tenant.slug:
        raise ProvisionError("Slug confirmation does not match.")
    tenant.refresh_from_db()
    if tenant.status == Tenant.Status.DELETED:
        return
    tenant.status = Tenant.Status.DELETING
    tenant.save(update_fields=["status"])
    dumper = dump if dump is not None else dump_tenant
    if _database_exists(tenant.db_name):
        job.step = "dump"
        job.save(update_fields=["step"])
        dumper(tenant)
    job.step = "drop"
    job.save(update_fields=["step"])
    _drop_database_and_role(tenant)
    tenant.domains.all().delete()
    tenant.status = Tenant.Status.DELETED
    tenant.deleted_at = timezone.now()
    tenant.save(update_fields=["status", "deleted_at"])


def purge_tenant(job):
    """Drop the database and login, then delete the registry row.

    No dump is taken. The maintenance connection owns the drop, so a tenant
    login with the wrong password does not block removal. Deleting the row
    frees the slug. The job row goes with it.
    """
    tenant = job.tenant
    confirm = (job.payload or {}).get("confirm_slug")
    if confirm != tenant.slug:
        raise ProvisionError("Slug confirmation does not match.")
    tenant.refresh_from_db()
    if tenant.status not in PURGEABLE_STATUSES:
        raise ProvisionError(
            "Only a failed or unfinished tenant can be removed without a backup."
        )
    _reject_purge_with_invoices(tenant)
    if tenant.status != Tenant.Status.DELETED:
        tenant.status = Tenant.Status.DELETING
        tenant.save(update_fields=["status"])
    job.step = "drop"
    job.save(update_fields=["step"])
    _drop_database_and_role(tenant)
    tenant.domains.all().delete()
    tenant.delete()


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
            suspend_tenant(job.tenant, (job.payload or {}).get("suspension_reason") or "")
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.RESUME:
            job.step = "resume"
            resume_tenant(job.tenant)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.DELETE:
            delete_tenant(job)
            _succeed(job)
        elif job.kind == ProvisionJob.Kind.PURGE:
            purge_tenant(job)
            if ProvisionJob.objects.filter(pk=job.pk).exists():
                _succeed(job)
        elif job.kind == ProvisionJob.Kind.BACKUP:
            job.step = "dump"
            job.save(update_fields=["step"])
            location = dump_tenant(job.tenant)
            payload = dict(job.payload or {})
            payload.update(_dump_payload(job.tenant.slug, location))
            pruned = _prune_after_backup(job.tenant.slug)
            if pruned:
                payload["pruned"] = pruned
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


def _dump_payload(slug: str, location: str) -> dict:
    """Job-payload fields naming the finished dump. Never a credential."""
    if not backup_store.configured():
        return {"dump_path": location}
    payload = {"dump_key": location}
    try:
        stored = backup_store.head(slug, location.rsplit("/", 1)[-1])
    except backup_store.BackupStoreError:
        stored = None
    if stored:
        payload["dump_bytes"] = stored["size"]
    return payload


def _prune_after_backup(slug: str) -> list[str]:
    """Retention runs after a good backup. Its failure never fails the job."""
    from control.backup import prune_backups

    try:
        return prune_backups(slug)
    except Exception:  # noqa: BLE001 - logged, backup already succeeded
        logger.exception("Backup retention failed for %s", slug)
        return []


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
        password = tenant.db_password()
        quoted = quote_ident(role)
        literal = _quote_literal(password)
        if _exists(cursor, "SELECT 1 FROM pg_roles WHERE rolname = %s", [role]):
            # A previous tenant left this login behind. The stored password is new.
            cursor.execute(f"ALTER ROLE {quoted} WITH LOGIN PASSWORD '{literal}'")
            return
        cursor.execute(f"CREATE ROLE {quoted} LOGIN PASSWORD '{literal}'")


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
    moment = timezone.now()
    tenant.activated_at = moment
    if (job.payload or {}).get("start_as_trial"):
        tenant.status = Tenant.Status.TRIALING
        days = TRIAL_DAYS
        if tenant.plan_fk_id and tenant.plan_fk.trial_days:
            days = tenant.plan_fk.trial_days
        tenant.trial_ends_at = moment + timedelta(days=days)
        tenant.save(update_fields=["status", "activated_at", "trial_ends_at"])
    else:
        tenant.status = Tenant.Status.ACTIVE
        tenant.trial_ends_at = None
        tenant.save(update_fields=["status", "activated_at", "trial_ends_at"])


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
