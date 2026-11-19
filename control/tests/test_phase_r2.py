"""Phase R2: readiness, heartbeat, retry, restore choices, and catalog audit."""

from datetime import date, timedelta
from unittest import mock

from django.test import Client, TestCase, override_settings
from django.test.utils import CaptureQueriesContext
from django.db import connection
from django.utils import timezone

from control.backup import list_dumps
from control.heartbeat import beat, heartbeat_status, provisioner_notice
from control.models import Invoice, Operator, OperatorAudit, Plan, ProvisionJob, Tenant
from control.provisioning import (
    ProvisionError,
    _run_restore,
    enqueue_purge,
    purge_tenant,
    terminate_tenant_sessions,
)
from control.readiness import tenant_migration_status

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "phase-r2",
            "KEY_PREFIX": "horilla",
            "KEY_FUNCTION": "horilla.cache.tenant_cache_key",
        }
    },
)

DUMP = "20261119T010203000000Z.dump"


def _operator(email="ops-r2@example.com"):
    operator = Operator(email=email, is_staff=True, is_active=True)
    operator.set_password("correct-horse")
    operator.save()
    return operator


def _tenant(slug, **kwargs):
    tenant = Tenant(
        name=kwargs.pop("name", slug.title()),
        slug=slug,
        status=kwargs.pop("status", Tenant.Status.ACTIVE),
    )
    for key, value in kwargs.items():
        setattr(tenant, key, value)
    tenant.save()
    return tenant


def _login(client, email="ops-r2@example.com"):
    return client.post(
        "/control/login/",
        {"email": email, "password": "correct-horse"},
    )


@MULTI
class MigrationReadinessTests(TestCase):
    def test_newest_migrate_wins_and_stays_on_the_control_database(self):
        tenant = _tenant("acmer2", status=Tenant.Status.ACTIVE)
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.FAILED,
            step="migrate",
        )
        self.assertEqual(tenant_migration_status(), "failed:acmer2")
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.SUCCEEDED,
            step="migrate",
        )
        with CaptureQueriesContext(connection) as captured:
            self.assertEqual(tenant_migration_status(), "ok")
        self.assertTrue(captured.captured_queries)
        for query in captured.captured_queries:
            self.assertIn("control_provisionjob", query["sql"])


@MULTI
class HeartbeatTests(TestCase):
    def setUp(self):
        super().setUp()
        from django.core.cache import cache

        cache.clear()

    def test_fresh_cache_notice_does_not_query_and_ready_reports_the_state(self):
        now = timezone.now()
        beat(now=now)
        with self.assertNumQueries(0):
            self.assertEqual(provisioner_notice(now=now), "")
            self.assertEqual(heartbeat_status(now=now)[0], "ok")
        response = Client().get("/ready/", HTTP_HOST="manage.localhost")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["provisioner"], "ok")

    def test_stale_beat_is_reported_and_queries_the_oldest_queued_job_once(self):
        moment = timezone.now()
        beat(now=moment - timedelta(minutes=5))
        tenant = _tenant("queueco", status=Tenant.Status.PROVISIONING)
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.QUEUED,
        )
        with self.assertNumQueries(1):
            text = provisioner_notice(now=moment)
        self.assertIn("last reported", text)
        self.assertIn("Oldest queued job", text)
        self.assertEqual(heartbeat_status(now=moment)[0], "stale")

    def test_missing_heartbeat_is_reported_without_failing_ready(self):
        response = Client().get("/ready/", HTTP_HOST="manage.localhost")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["provisioner"], "missing")
        self.assertIn("has not reported yet", provisioner_notice())

    def test_dashboard_shows_the_banner_when_the_provisioner_is_stale(self):
        _operator()
        client = Client(HTTP_HOST="manage.localhost")
        _login(client)
        beat(now=timezone.now() - timedelta(minutes=5))
        home = client.get("/control/")
        self.assertContains(home, "The provisioner last reported")


@MULTI
class RetryViewTests(TestCase):
    def setUp(self):
        super().setUp()
        _operator()
        self.client = Client(HTTP_HOST="manage.localhost")
        _login(self.client)

    def test_retry_button_and_post_continue_completed_steps(self):
        active = _tenant("liveco", status=Tenant.Status.ACTIVE)
        page = self.client.get(f"/control/tenants/{active.slug}/")
        self.assertNotContains(page, ">Retry</button>")
        refused = self.client.post(f"/control/tenants/{active.slug}/retry/")
        self.assertEqual(refused.status_code, 400)
        self.assertContains(refused, "Only a failed tenant can be retried.", status_code=400)

        failed = _tenant("failr2", status=Tenant.Status.FAILED)
        ProvisionJob.objects.create(
            tenant=failed,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.FAILED,
            payload={"completed_steps": ["create_database", "create_role"]},
        )
        failed_page = self.client.get(f"/control/tenants/{failed.slug}/")
        self.assertContains(failed_page, ">Retry</button>")
        queued = self.client.post(f"/control/tenants/{failed.slug}/retry/")
        self.assertEqual(queued.status_code, 302)
        failed.refresh_from_db()
        self.assertEqual(failed.status, Tenant.Status.PROVISIONING)
        job = failed.jobs.order_by("-pk").first()
        self.assertEqual(job.status, ProvisionJob.Status.QUEUED)
        self.assertEqual(
            job.payload["completed_steps"],
            ["create_database", "create_role"],
        )
        audit = OperatorAudit.objects.get(slug="failr2", action=OperatorAudit.Action.CREATE)
        self.assertEqual(audit.detail, "Queued retry.")


@MULTI
class RestoreChoiceTests(TestCase):
    def setUp(self):
        super().setUp()
        _operator()
        self.client = Client(HTTP_HOST="manage.localhost")
        _login(self.client)
        self.tenant = _tenant("dumpco", status=Tenant.Status.ACTIVE)

    def test_dropdown_lists_only_this_tenants_dumps_and_rejects_other_names(self):
        own = {
            "name": DUMP,
            "size": 24,
            "last_modified": timezone.now(),
        }
        with mock.patch("control.backup.list_dumps", return_value=[own]):
            page = self.client.get(f"/control/tenants/{self.tenant.slug}/")
            self.assertContains(page, DUMP)
            self.assertContains(page, "24 B")
            self.assertContains(page, ">Restore</button>")
            accepted = self.client.post(
                f"/control/tenants/{self.tenant.slug}/restore/",
                {"dump_name": DUMP},
            )
        self.assertEqual(accepted.status_code, 302)
        job = self.tenant.jobs.get(kind=ProvisionJob.Kind.RESTORE)
        self.assertEqual(job.payload["dump_name"], DUMP)

        with mock.patch("control.backup.list_dumps", return_value=[own]):
            foreign = self.client.post(
                f"/control/tenants/{self.tenant.slug}/restore/",
                {"dump_name": "other-tenant.dump"},
            )
        self.assertEqual(foreign.status_code, 400)
        self.assertContains(foreign, "not valid", status_code=400)
        self.assertEqual(
            self.tenant.jobs.filter(kind=ProvisionJob.Kind.RESTORE).count(),
            1,
        )

    def test_empty_backup_list_has_no_restore_form(self):
        with mock.patch("control.backup.list_dumps", return_value=[]):
            page = self.client.get(f"/control/tenants/{self.tenant.slug}/")
        self.assertContains(page, "No backups yet.")
        self.assertNotContains(page, ">Restore</button>")

    def test_list_dumps_reads_only_the_named_slug_folder(self):
        from pathlib import Path

        from django.conf import settings

        root = Path(settings.BASE_DIR) / "backups"
        own = root / "slugco"
        other = root / "otherco"
        own.mkdir(parents=True, exist_ok=True)
        other.mkdir(parents=True, exist_ok=True)
        (own / DUMP).write_bytes(b"own")
        (other / "20261119T020000000000Z.dump").write_bytes(b"other")
        (own / ".spool.dump").write_bytes(b"temp")
        try:
            with mock.patch("control.backup.backup_store.configured", return_value=False):
                names = [entry["name"] for entry in list_dumps("slugco")]
        finally:
            (own / DUMP).unlink(missing_ok=True)
            (own / ".spool.dump").unlink(missing_ok=True)
            (other / "20261119T020000000000Z.dump").unlink(missing_ok=True)
        self.assertEqual(names, [DUMP])

    def test_non_staff_can_see_backups_but_not_restore(self):
        viewer = Operator(email="viewer-r2@example.com", is_staff=False, is_active=True)
        viewer.set_password("correct-horse")
        viewer.save()
        client = Client(HTTP_HOST="manage.localhost")
        client.post(
            "/control/login/",
            {"email": viewer.email, "password": "correct-horse"},
        )
        own = {
            "name": DUMP,
            "size": 24,
            "last_modified": timezone.now(),
        }
        with mock.patch("control.backup.list_dumps", return_value=[own]):
            page = client.get(f"/control/tenants/{self.tenant.slug}/")
        self.assertContains(page, DUMP)
        self.assertContains(page, "Backups")
        self.assertNotContains(page, ">Restore</button>")


@MULTI
class CatalogAuditTests(TestCase):
    def setUp(self):
        super().setUp()
        _operator("catalog-r2@example.com")
        self.client = Client(HTTP_HOST="manage.localhost")
        _login(self.client, "catalog-r2@example.com")

    def _plan_payload(self, code, monthly):
        return {
            "code": code,
            "name": code.title(),
            "status": "active",
            "price_monthly": str(monthly),
            "price_semiannual": "500",
            "price_annual": "900",
            "trial_days": "14",
            "setup_fee": "0",
            "sort_order": "0",
        }

    def test_plan_create_edit_and_archive_are_audited(self):
        created = self.client.post("/control/plans/new/", self._plan_payload("ridge", 100))
        self.assertEqual(created.status_code, 302)
        row = OperatorAudit.objects.get(action=OperatorAudit.Action.CATALOG_UPDATE)
        self.assertEqual(row.category, OperatorAudit.Category.BILLING)
        self.assertIn("plan ridge: none ->", row.detail)
        self.assertIn("monthly 100", row.detail)
        self.assertNotIn("correct-horse", row.detail)
        self.assertNotIn("postgres://", row.detail)

        edited = self.client.post(
            "/control/plans/ridge/edit/",
            self._plan_payload("ridge", 120),
        )
        self.assertEqual(edited.status_code, 302)
        edit_row = OperatorAudit.objects.filter(
            action=OperatorAudit.Action.CATALOG_UPDATE
        ).order_by("-pk").first()
        self.assertIn("monthly 100", edit_row.detail)
        self.assertIn("monthly 120", edit_row.detail)

        tenant = _tenant("ridgeco", status=Tenant.Status.ACTIVE)
        tenant.plan_fk = Plan.objects.get(code="ridge")
        tenant.save(update_fields=["plan_fk"])
        archived = self.client.post("/control/plans/ridge/delete/")
        self.assertEqual(archived.status_code, 302)
        plan = Plan.objects.get(code="ridge")
        self.assertEqual(plan.status, Plan.Status.ARCHIVED)
        archive_row = OperatorAudit.objects.filter(
            action=OperatorAudit.Action.CATALOG_UPDATE
        ).order_by("-pk").first()
        self.assertIn("archived", archive_row.detail)


@MULTI
class PurgeInvoiceTests(TestCase):
    def _invoice(self, tenant):
        today = date.today()
        return Invoice.objects.create(
            tenant=tenant,
            plan_code="starter",
            cadence=Tenant.Cadence.MONTHLY,
            seat_count=1,
            amount_rupees=100,
            period_label="Nov 2026",
            issued_on=today,
            due_on=today,
        )

    def test_invoices_block_purge_and_a_failed_tenant_without_them_can_queue(self):
        billed = _tenant("billedr2", status=Tenant.Status.FAILED)
        self._invoice(billed)
        with self.assertRaises(ProvisionError) as queued:
            enqueue_purge(billed, "billedr2")
        self.assertIn("Void or resolve", str(queued.exception))
        job = ProvisionJob.objects.create(
            tenant=billed,
            kind=ProvisionJob.Kind.PURGE,
            status=ProvisionJob.Status.RUNNING,
            payload={"confirm_slug": "billedr2"},
        )
        with mock.patch("control.provisioning._drop_database_and_role") as drop:
            with self.assertRaises(ProvisionError) as running:
                purge_tenant(job)
        self.assertIn("Void or resolve", str(running.exception))
        drop.assert_not_called()

        clean = _tenant("cleanr2", status=Tenant.Status.FAILED, db_name="tenant_cleanr2")
        queued_job = enqueue_purge(clean, "cleanr2")
        self.assertEqual(queued_job.kind, ProvisionJob.Kind.PURGE)
        with mock.patch("control.provisioning._drop_database_and_role"):
            purge_tenant(queued_job)
        self.assertFalse(Tenant.objects.filter(slug="cleanr2").exists())


@MULTI
class RestoreSessionTests(TestCase):
    def test_terminate_runs_before_restore_and_success_queues_migrate(self):
        tenant = _tenant("restorer2", status=Tenant.Status.ACTIVE, db_name="tenant_restorer2")
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.RESTORE,
            status=ProvisionJob.Status.RUNNING,
            payload={"dump_name": DUMP, "status_before": Tenant.Status.ACTIVE},
        )
        seen = []

        def spy(current):
            job.refresh_from_db()
            seen.append((job.step, current.db_name))

        with (
            mock.patch("control.provisioning.terminate_tenant_sessions", side_effect=spy),
            mock.patch("control.backup.restore_tenant_database"),
        ):
            _run_restore(job)
        self.assertEqual(seen, [("terminate", "tenant_restorer2")])
        self.assertTrue(
            tenant.jobs.filter(
                kind=ProvisionJob.Kind.MIGRATE,
                status=ProvisionJob.Status.QUEUED,
            ).exists()
        )

    def test_failed_restore_does_not_queue_migrate(self):
        tenant = _tenant("heldr2", status=Tenant.Status.ACTIVE, db_name="tenant_heldr2")
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.RESTORE,
            status=ProvisionJob.Status.RUNNING,
            payload={"dump_name": DUMP, "status_before": Tenant.Status.ACTIVE},
        )
        with (
            mock.patch("control.provisioning.terminate_tenant_sessions"),
            mock.patch(
                "control.backup.restore_tenant_database",
                side_effect=ProvisionError("restore failed"),
            ),
        ):
            with self.assertRaises(ProvisionError):
                _run_restore(job)
        self.assertFalse(tenant.jobs.filter(kind=ProvisionJob.Kind.MIGRATE).exists())
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.SUSPENDED)

    def test_terminate_targets_the_tenant_database_and_refuses_the_control_database(self):
        from django.conf import settings

        tenant = _tenant("gateco", status=Tenant.Status.ACTIVE)
        cursor = mock.Mock()
        cursor.__enter__ = mock.Mock(return_value=cursor)
        cursor.__exit__ = mock.Mock(return_value=False)
        tenant.db_name = "tenant_gateco"
        with mock.patch("control.provisioning.maintenance_cursor", return_value=cursor):
            terminate_tenant_sessions(tenant)
        sql, params = cursor.execute.call_args[0]
        self.assertIn("pg_terminate_backend", sql)
        self.assertEqual(params, ["tenant_gateco"])

        cursor.reset_mock()
        tenant.db_name = settings.DATABASES["default"]["NAME"]
        with mock.patch("control.provisioning.maintenance_cursor", return_value=cursor):
            terminate_tenant_sessions(tenant)
        cursor.execute.assert_not_called()
