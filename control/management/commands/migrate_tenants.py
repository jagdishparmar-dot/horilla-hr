"""Migrate every active tenant database. One failure does not stop the rest."""

from django.core.management import call_command
from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone

from control.context import activate_tenant_alias, clear_tenant_alias
from control.crypto import redact_job_error
from control.db import ensure_tenant_connection
from control.models import ProvisionJob, Tenant


class Command(BaseCommand):
    help = (
        "Run migrate on each active tenant database. "
        "Suspended tenants are skipped unless --include-suspended is set."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--include-suspended",
            action="store_true",
            help="Also migrate tenants whose status is suspended.",
        )

    def handle(self, *args, **options):
        statuses = [Tenant.Status.ACTIVE]
        if options["include_suspended"]:
            statuses.append(Tenant.Status.SUSPENDED)
        tenants = list(Tenant.objects.filter(status__in=statuses).order_by("slug"))
        if not tenants:
            self.stdout.write("No tenant databases to migrate.")
            return

        failed = 0
        for tenant in tenants:
            if not self._migrate_one(tenant):
                failed += 1
        if failed:
            raise CommandError(f"{failed} tenant migration(s) failed.")

    def _migrate_one(self, tenant) -> bool:
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.RUNNING,
            step="migrate",
            started_at=timezone.now(),
        )
        token = None
        try:
            alias = ensure_tenant_connection(tenant)
            token = activate_tenant_alias(alias)
            call_command("migrate", database=alias, interactive=False, verbosity=1)
        except Exception as exc:
            job.status = ProvisionJob.Status.FAILED
            job.set_error(f"{type(exc).__name__}: {exc}")
            job.finished_at = timezone.now()
            job.save(update_fields=["status", "error", "finished_at"])
            self.stderr.write(f"{tenant.slug}: {redact_job_error(str(exc))}")
            return False
        else:
            job.status = ProvisionJob.Status.SUCCEEDED
            job.finished_at = timezone.now()
            job.save(update_fields=["status", "finished_at"])
            self.stdout.write(f"{tenant.slug}: migrated")
            return True
        finally:
            clear_tenant_alias(token)
