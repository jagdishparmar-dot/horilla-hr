"""Phase 5 health panel and categorized audit log."""

import os
from datetime import timedelta
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, TestCase, override_settings
from django.utils import timezone

from control.audit import backfill_audit_categories, record_operator_action
from control.backup import backup_dir
from control.health import tenant_health
from control.models import Operator, OperatorAudit, ProvisionJob, Tenant

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _operator(email="health-ops@example.com"):
    operator = Operator(email=email, is_staff=True, is_active=True)
    operator.set_password("correct-horse")
    operator.save()
    return operator


def _tenant(slug, **kwargs):
    tenant = Tenant(
        name=kwargs.pop("name", slug.title()),
        slug=slug,
        status=kwargs.pop("status", Tenant.Status.ACTIVE),
        db_name=f"tenant_{slug}",
        db_user=f"tenant_{slug}",
    )
    for key, value in kwargs.items():
        setattr(tenant, key, value)
    tenant.save()
    return tenant


def _by_name(lines):
    return {line.name: line for line in lines}


@MULTI
class TenantHealthTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator()

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_missing_backup_fails_that_line_only(self):
        tenant = _tenant("healthco", used_storage_gb=1, storage_limit_gb=10)
        with mock.patch("control.health._probe_connection"):
            lines = _by_name(tenant_health(tenant))
        self.assertEqual(lines["backup"].status, "failed")
        self.assertEqual(lines["connection"].status, "healthy")
        self.assertEqual(lines["migrate"].status, "healthy")
        self.assertEqual(lines["storage"].status, "healthy")
        blob = " ".join(line.detail for line in lines.values())
        self.assertNotIn("password", blob.lower())
        self.assertNotIn("postgres://", blob)

    def test_connection_failure_hides_the_exception(self):
        tenant = _tenant("leakco")
        with mock.patch(
            "control.health._probe_connection",
            side_effect=RuntimeError("postgres://role:db-secret-value@db/tenant_leakco"),
        ):
            lines = _by_name(tenant_health(tenant))
        self.assertEqual(lines["connection"].status, "failed")
        self.assertNotIn("db-secret-value", lines["connection"].detail)
        self.assertNotIn("postgres://", lines["connection"].detail)

    def test_storage_at_85_percent_is_degraded(self):
        full = _tenant("fullco", used_storage_gb=85, storage_limit_gb=100)
        room = _tenant("roomco", used_storage_gb=84, storage_limit_gb=100)
        with mock.patch("control.health._probe_connection"):
            self.assertEqual(_by_name(tenant_health(full))["storage"].status, "degraded")
            self.assertEqual(_by_name(tenant_health(room))["storage"].status, "healthy")

    def test_backup_file_age(self):
        tenant = _tenant("dumpco")
        folder = backup_dir(tenant.slug)
        folder.mkdir(parents=True, exist_ok=True)
        dump = folder / "recent.dump"
        dump.write_bytes(b"dump")
        self.addCleanup(dump.unlink, missing_ok=True)
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
            payload={"dump_path": str(dump)},
            finished_at=timezone.now() - timedelta(days=8),
        )
        with mock.patch("control.health._probe_connection"):
            self.assertEqual(_by_name(tenant_health(tenant))["backup"].status, "degraded")
        job.finished_at = timezone.now()
        job.save(update_fields=["finished_at"])
        with mock.patch("control.health._probe_connection"):
            self.assertEqual(_by_name(tenant_health(tenant))["backup"].status, "healthy")
        job.payload = {"dump_path": str(folder / "missing.dump")}
        job.save(update_fields=["payload"])
        with mock.patch("control.health._probe_connection"):
            self.assertEqual(_by_name(tenant_health(tenant))["backup"].status, "failed")

    def test_newer_failed_backup_keeps_succeeded_dump(self):
        tenant = _tenant("keepco")
        folder = backup_dir(tenant.slug)
        folder.mkdir(parents=True, exist_ok=True)
        dump = folder / "kept.dump"
        dump.write_bytes(b"dump")
        self.addCleanup(dump.unlink, missing_ok=True)
        now = timezone.now()
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
            payload={"dump_path": str(dump)},
            finished_at=now,
        )
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.FAILED,
            finished_at=now + timedelta(minutes=1),
        )
        with mock.patch("control.health._probe_connection"):
            backup = _by_name(tenant_health(tenant))["backup"]
        self.assertEqual(backup.status, "healthy")
        self.assertEqual(backup.detail, "Newest backup is present.")

    def test_trialing_migrate_is_healthy_until_newest_failure(self):
        trialing = _tenant("trialco", status=Tenant.Status.TRIALING)
        with mock.patch("control.health._probe_connection"):
            migrate = _by_name(tenant_health(trialing))["migrate"]
        self.assertEqual(migrate.status, "healthy")
        self.assertEqual(migrate.detail, "No failed migrate.")

        past_due = _tenant("dueco", status=Tenant.Status.PAST_DUE)
        with mock.patch("control.health._probe_connection"):
            due = _by_name(tenant_health(past_due))["migrate"]
        self.assertEqual(due.status, "healthy")
        self.assertEqual(due.detail, "No failed migrate.")

        provisioning = _tenant("newco", status=Tenant.Status.PROVISIONING)
        ProvisionJob.objects.create(
            tenant=provisioning,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.SUCCEEDED,
        )
        with mock.patch("control.health._probe_connection"):
            created = _by_name(tenant_health(provisioning))["migrate"]
        self.assertEqual(created.status, "healthy")
        self.assertEqual(created.detail, "Create succeeded.")

        tenant = _tenant("flipco")
        now = timezone.now()
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.SUCCEEDED,
            finished_at=now,
        )
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.FAILED,
            finished_at=now - timedelta(days=3),
        )
        with mock.patch("control.health._probe_connection"):
            failed = _by_name(tenant_health(tenant))["migrate"]
        self.assertEqual(failed.status, "failed")
        self.assertEqual(failed.detail, "Migrate has not succeeded.")

    def test_button_runs_checks_for_that_slug(self):
        tenant = _tenant("buttonco")
        self.client.post(
            "/control/login/",
            {"email": "health-ops@example.com", "password": "correct-horse"},
        )
        quiet = self.client.get(f"/control/tenants/{tenant.slug}/")
        self.assertContains(quiet, "Health checks have not been run.")
        self.assertNotContains(quiet, "No successful backup.")
        with mock.patch("control.health._probe_connection"):
            ran = self.client.post(f"/control/tenants/{tenant.slug}/health/")
        self.assertEqual(ran.status_code, 200)
        self.assertContains(ran, "No successful backup.")
        self.assertContains(ran, "Tenant role opened the database.")
        self.assertEqual(tenant.jobs.count(), 0)


@MULTI
class AuditCategoryTests(TestCase):
    def setUp(self):
        super().setUp()
        self.operator = _operator("audit-ops@example.com")

    def test_backfill_maps_backup_and_invoice_issue(self):
        backup = OperatorAudit.objects.create(
            operator=self.operator,
            action=OperatorAudit.Action.BACKUP,
            slug="backupco",
            detail="queued backup",
        )
        invoice = OperatorAudit.objects.create(
            operator=self.operator,
            action=OperatorAudit.Action.INVOICE_ISSUE,
            slug="billco",
            detail="issued",
        )
        security = OperatorAudit.objects.create(
            operator=self.operator,
            action=OperatorAudit.Action.OPERATOR_CREATE,
            detail="added",
        )
        OperatorAudit.objects.filter(pk=backup.pk).update(
            category=OperatorAudit.Category.BILLING
        )
        OperatorAudit.objects.filter(pk=invoice.pk).update(
            category=OperatorAudit.Category.PROVISIONING
        )
        OperatorAudit.objects.filter(pk=security.pk).update(
            category=OperatorAudit.Category.PROVISIONING
        )
        backfill_audit_categories()
        backup.refresh_from_db()
        invoice.refresh_from_db()
        security.refresh_from_db()
        self.assertEqual(backup.category, OperatorAudit.Category.PROVISIONING)
        self.assertEqual(invoice.category, OperatorAudit.Category.BILLING)
        self.assertEqual(security.category, OperatorAudit.Category.SECURITY)

    def test_new_invoice_action_is_billing(self):
        row = record_operator_action(
            operator=self.operator,
            action=OperatorAudit.Action.INVOICE_ISSUE,
            slug="billco",
            detail="issued",
        )
        self.assertEqual(row.category, OperatorAudit.Category.BILLING)


@MULTI
class AuditPageTests(TestCase):
    def setUp(self):
        super().setUp()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("page-ops@example.com")
        self.client.post(
            "/control/login/",
            {"email": "page-ops@example.com", "password": "correct-horse"},
        )
        self.live = _tenant("linkco")
        OperatorAudit.objects.create(
            operator=self.operator,
            action=OperatorAudit.Action.BACKUP,
            slug="linkco",
            detail="provisioning-only-marker",
        )
        OperatorAudit.objects.create(
            operator=self.operator,
            action=OperatorAudit.Action.INVOICE_ISSUE,
            slug="goneco",
            detail="setup_password=hunter2 postgres://role:db-secret-value@db/tenant_goneco billing-only-marker",
        )

    def test_filter_hides_other_categories_and_secrets(self):
        page = self.client.get("/control/audit/?category=billing")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "billing-only-marker")
        self.assertNotContains(page, "provisioning-only-marker")
        self.assertNotContains(page, "setup_password")
        self.assertNotContains(page, "hunter2")
        self.assertNotContains(page, "db-secret-value")
        self.assertNotContains(page, "postgres://")
        self.assertNotContains(page, 'href="/control/tenants/goneco/"')
        linked = self.client.get("/control/audit/?category=provisioning")
        self.assertContains(linked, 'href="/control/tenants/linkco/"')
        self.assertNotContains(linked, "billing-only-marker")
