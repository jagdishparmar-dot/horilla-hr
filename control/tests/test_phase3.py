import os
from datetime import timedelta
from unittest import mock

from cryptography.fernet import Fernet
from django.contrib.auth import get_user_model
from django.test import RequestFactory, TestCase, override_settings
from django.urls import Resolver404, resolve
from django.utils import timezone

from base.models import Company
from control.middleware import TenantMiddleware
from control.models import Domain, Invoice, ProvisionJob, Tenant
from control.provisioning import (
    PROVISION_STALE_AFTER,
    ProvisionError,
    _step_create_database,
    _step_create_role,
    _step_grant_connect,
    _step_revoke_other_roles,
    _step_revoke_public,
    delete_tenant,
    dump_tenant,
    enqueue_backup,
    enqueue_create,
    enqueue_delete,
    enqueue_purge,
    enqueue_migrate,
    enqueue_restore,
    enqueue_resume,
    enqueue_retry,
    enqueue_suspend,
    lock_control_connect,
    maintenance_cursor,
    process_available_jobs,
    quote_catalog_ident,
    quote_ident,
    reclaim_stale_jobs,
    seed_tenant,
)
from django.http import HttpResponse, HttpResponseNotFound


def _key():
    return mock.patch.dict(
        os.environ,
        {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
    )


def _invoice(tenant, status):
    today = timezone.localdate()
    return Invoice.objects.create(
        tenant=tenant,
        plan_code="starter",
        cadence=Tenant.Cadence.MONTHLY,
        seat_count=1,
        amount_rupees=100,
        status=status,
        period_label="November 2026",
        issued_on=today,
        due_on=today,
    )


class ProvisionQueueTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = _key()
        self._env.start()

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def _patch_sql(self):
        names = [
            "_step_create_role",
            "_step_create_database",
            "_step_revoke_public",
            "_step_grant_connect",
            "_step_revoke_other_roles",
            "_step_store_connection",
            "_step_migrate",
            "_step_seed",
        ]
        patches = []
        calls = []
        for name in names:
            def recorder(job, label=name):
                calls.append(label)

            patches.append(
                mock.patch(f"control.provisioning.{name}", side_effect=recorder)
            )
        for item in patches:
            item.start()
            self.addCleanup(item.stop)
        return calls

    def test_create_reaches_active_only_after_migrate_and_seed(self):
        calls = self._patch_sql()
        job = enqueue_create(name="Acme", slug="acme", plan="starter")
        setup_password = job.tenant.setup_password()
        self.assertTrue(setup_password)
        self.assertNotIn(setup_password, str(job))
        self.assertNotIn(setup_password, str(job.payload))
        process_available_jobs()
        job.refresh_from_db()
        job.tenant.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.SUCCEEDED)
        self.assertLess(calls.index("_step_migrate"), calls.index("_step_seed"))
        self.assertEqual(job.tenant.status, Tenant.Status.ACTIVE)
        domain = Domain.objects.get(tenant=job.tenant)
        self.assertEqual(domain.host, "acme.localhost")
        self.assertTrue(domain.is_primary)
        self.assertTrue(domain.verified)

        request = RequestFactory().get("/login/", HTTP_HOST="acme.localhost")

        def get_response(req):
            match = resolve(req.path_info, urlconf=req.urlconf)
            return HttpResponse(match.url_name)

        with override_settings(
            HORILLA_MULTITENANT=True,
            HORILLA_PLATFORM_DOMAIN="localhost",
            HORILLA_DASHBOARD_HOST="manage.localhost",
            ALLOWED_HOSTS=[".localhost", "manage.localhost"],
        ), mock.patch(
            "control.middleware.ensure_tenant_connection",
            return_value="tenant_acme",
        ):
            response = TenantMiddleware(get_response)(request)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, b"login")

    def test_migrate_failure_does_not_publish_a_domain(self):
        self._patch_sql()
        with mock.patch(
            "control.provisioning._step_migrate",
            side_effect=ProvisionError("migrate failed"),
        ):
            job = enqueue_create(name="Beta", slug="beta")
            process_available_jobs()
        job.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.FAILED)
        self.assertEqual(job.step, "migrate")
        self.assertEqual(job.tenant.status, Tenant.Status.FAILED)
        self.assertFalse(Domain.objects.filter(tenant=job.tenant).exists())
        self.assertNotIn(job.tenant.setup_password(), job.error)

    def test_retry_skips_a_finished_create_database_step(self):
        calls = self._patch_sql()
        with mock.patch(
            "control.provisioning._step_migrate",
            side_effect=ProvisionError("migrate failed"),
        ):
            job = enqueue_create(name="Acme", slug="acme")
            process_available_jobs()
        self.assertIn("_step_create_database", calls)
        calls.clear()
        enqueue_retry(job.tenant)
        process_available_jobs()
        self.assertNotIn("_step_create_database", calls)
        self.assertIn("_step_migrate", calls)
        retry = ProvisionJob.objects.order_by("-pk").first()
        self.assertEqual(retry.step, "activate")

    def test_suspend_keeps_the_database_and_resume_does_not_create_one(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
        )
        Domain.objects.create(
            tenant=tenant,
            host="acme.localhost",
            is_primary=True,
            verified=True,
        )
        enqueue_suspend(tenant)
        process_available_jobs()
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.SUSPENDED)
        self.assertTrue(Domain.objects.filter(host="acme.localhost").exists())
        request = RequestFactory().get("/login/", HTTP_HOST="acme.localhost")
        with override_settings(
            HORILLA_MULTITENANT=True,
            HORILLA_PLATFORM_DOMAIN="localhost",
            HORILLA_DASHBOARD_HOST="manage.localhost",
            ALLOWED_HOSTS=[".localhost", "manage.localhost"],
        ):
            response = TenantMiddleware(lambda req: HttpResponse("ok"))(request)
        self.assertEqual(response.status_code, 403)

        with mock.patch(
            "control.provisioning._database_exists", return_value=True
        ) as exists, mock.patch(
            "control.provisioning._step_create_database"
        ) as create_db:
            enqueue_resume(tenant)
            process_available_jobs()
        exists.assert_called()
        create_db.assert_not_called()
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)

    def test_delete_dumps_before_drop_and_the_host_is_gone(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
            db_user="tenant_acme",
        )
        Domain.objects.create(
            tenant=tenant,
            host="acme.localhost",
            is_primary=True,
            verified=True,
        )
        with self.assertRaises(ProvisionError):
            enqueue_delete(tenant, "other")
        events = []
        with mock.patch(
            "control.provisioning._database_exists", return_value=True
        ), mock.patch(
            "control.provisioning.dump_tenant",
            side_effect=lambda tenant: events.append("dump"),
        ), mock.patch(
            "control.provisioning._drop_database_and_role",
            side_effect=lambda tenant: events.append("drop"),
        ):
            enqueue_delete(tenant, "acme")
            process_available_jobs()
        self.assertEqual(events, ["dump", "drop"])
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.DELETED)
        self.assertIsNotNone(tenant.deleted_at)
        self.assertFalse(Domain.objects.filter(host="acme.localhost").exists())

        request = RequestFactory().get("/login/", HTTP_HOST="acme.localhost")

        def get_response(req):
            try:
                resolve(req.path_info, urlconf=req.urlconf)
            except Resolver404:
                return HttpResponseNotFound("missing")
            return HttpResponse("ok")

        with override_settings(
            HORILLA_MULTITENANT=True,
            HORILLA_PLATFORM_DOMAIN="localhost",
            HORILLA_DASHBOARD_HOST="manage.localhost",
            ALLOWED_HOSTS=[".localhost", "manage.localhost"],
        ):
            response = TenantMiddleware(get_response)(request)
        self.assertEqual(response.status_code, 404)

    def test_stale_running_job_is_reclaimed(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.PROVISIONING,
        )
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.RUNNING,
            started_at=timezone.now() - PROVISION_STALE_AFTER - timedelta(minutes=1),
            step="create_database",
        )
        self.assertEqual(reclaim_stale_jobs(), 1)
        job.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.FAILED)
        self.assertEqual(tenant.status, Tenant.Status.FAILED)
        self.assertNotIn("password", job.error.lower())

    def test_jobs_run_one_at_a_time(self):
        from control.provisioning import suspend_tenant as real_suspend

        first = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.ACTIVE
        )
        second = Tenant.objects.create(
            name="Beta", slug="beta", status=Tenant.Status.ACTIVE
        )
        enqueue_suspend(first)
        enqueue_suspend(second)
        queued_while_running = []

        def spy(tenant, reason=""):
            queued_while_running.append(
                ProvisionJob.objects.filter(status=ProvisionJob.Status.QUEUED).count()
            )
            real_suspend(tenant, reason)

        with mock.patch("control.provisioning.suspend_tenant", side_effect=spy):
            processed = process_available_jobs()
        self.assertEqual(processed, 2)
        self.assertEqual(queued_while_running, [1, 0])

    def test_scheduler_and_command_drain_the_queue(self):
        import control.scheduler
        from io import StringIO

        from django.core.management import call_command

        from horilla.scheduling import _REGISTRY

        self.assertNotIn("control.scheduler.provision_queued_tenants", _REGISTRY)
        self.assertFalse(hasattr(control.scheduler, "provision_queued_tenants"))
        tenant = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.ACTIVE
        )
        enqueue_suspend(tenant)
        out = StringIO()
        call_command("run_provisioner", "--once", stdout=out)
        self.assertIn("reclaimed=0 processed=1", out.getvalue())
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.SUSPENDED)

    def test_restart_requeues_a_running_create_and_finishes_after_migrate(self):
        from io import StringIO

        from django.core.management import call_command

        calls = self._patch_sql()
        tenant = Tenant.objects.create(
            name="Cold",
            slug="cold",
            status=Tenant.Status.PROVISIONING,
        )
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.RUNNING,
            started_at=timezone.now(),
            step="migrate",
            payload={
                "completed_steps": [
                    "validate",
                    "create_role",
                    "create_database",
                    "revoke_public",
                    "grant_connect",
                    "revoke_other_roles",
                    "store_connection",
                ]
            },
        )
        seen = []

        def watch_migrate(running):
            running.tenant.refresh_from_db()
            seen.append(running.tenant.status)

        with mock.patch("control.provisioning._step_migrate", side_effect=watch_migrate):
            out = StringIO()
            call_command("run_provisioner", "--once", stdout=out)
        self.assertIn("requeued=1", out.getvalue())
        self.assertEqual(seen, [Tenant.Status.PROVISIONING])
        self.assertNotIn("_step_create_database", calls)
        self.assertIn("_step_seed", calls)
        job.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.SUCCEEDED)
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)
        self.assertTrue(Domain.objects.filter(tenant=tenant, is_primary=True).exists())

    def test_seed_does_not_create_an_admin(self):
        tenant = Tenant.objects.create(name="Acme", slug="acme", status=Tenant.Status.PROVISIONING)
        with override_settings(HORILLA_MULTITENANT=False):
            before_users = get_user_model().objects.count()
            before_companies = Company.objects.count()
            seed_tenant(tenant, {"plan": "standard"})
            seed_tenant(tenant, {"plan": "standard"})
            self.assertEqual(get_user_model().objects.count(), before_users)
            self.assertEqual(Company.objects.count(), before_companies)

    def test_dump_is_required_before_a_real_delete(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
        )
        tenant.set_db_password("db-secret")
        tenant.save(update_fields=["db_password_encrypted"])
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.RUNNING,
            payload={"confirm_slug": "acme"},
        )
        with mock.patch("control.provisioning._database_exists", return_value=True):
            with self.assertRaises(ProvisionError):
                delete_tenant(job)
        self.assertTrue(dump_tenant)  # the default hook is what refused
        tenant.refresh_from_db()
        self.assertNotEqual(tenant.status, Tenant.Status.DELETED)

    def test_delete_skips_the_dump_when_the_database_is_gone(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
            db_user="tenant_acme",
        )
        Domain.objects.create(
            tenant=tenant,
            host="acme.localhost",
            is_primary=True,
            verified=True,
        )
        with mock.patch(
            "control.provisioning._database_exists", return_value=False
        ), mock.patch(
            "control.provisioning.dump_tenant"
        ) as dump, mock.patch(
            "control.provisioning._drop_database_and_role"
        ) as drop:
            enqueue_delete(tenant, "acme")
            process_available_jobs()
        dump.assert_not_called()
        drop.assert_called_once()
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.DELETED)
        self.assertIsNotNone(tenant.deleted_at)
        self.assertFalse(Domain.objects.filter(host="acme.localhost").exists())

    def test_second_delete_after_deleted_succeeds_and_stays_deleted(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
            db_user="tenant_acme",
        )
        first = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.QUEUED,
            payload={"confirm_slug": "acme"},
        )
        second = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.QUEUED,
            payload={"confirm_slug": "acme"},
        )
        with mock.patch(
            "control.provisioning._database_exists", return_value=True
        ), mock.patch(
            "control.provisioning.dump_tenant"
        ) as dump, mock.patch(
            "control.provisioning._drop_database_and_role"
        ) as drop:
            self.assertEqual(process_available_jobs(), 2)
        dump.assert_called_once()
        drop.assert_called_once()
        first.refresh_from_db()
        second.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(first.status, ProvisionJob.Status.SUCCEEDED)
        self.assertEqual(second.status, ProvisionJob.Status.SUCCEEDED)
        self.assertEqual(tenant.status, Tenant.Status.DELETED)
        with self.assertRaises(ProvisionError):
            enqueue_delete(tenant, "acme")

    def test_enqueue_delete_rejects_a_queued_delete_and_a_deleting_tenant(self):
        tenant = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.ACTIVE
        )
        enqueue_delete(tenant, "acme")
        with self.assertRaises(ProvisionError):
            enqueue_delete(tenant, "acme")
        tenant.jobs.update(status=ProvisionJob.Status.FAILED)
        tenant.status = Tenant.Status.DELETING
        tenant.save(update_fields=["status"])
        with self.assertRaises(ProvisionError):
            enqueue_delete(tenant, "acme")

    def test_purge_drops_without_a_dump_and_frees_the_slug(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.FAILED,
            db_name="tenant_acme",
            db_user="tenant_acme",
        )
        Domain.objects.create(
            tenant=tenant,
            host="acme.localhost",
            is_primary=True,
            verified=True,
        )
        with self.assertRaises(ProvisionError):
            enqueue_purge(tenant, "other")
        with mock.patch("control.provisioning.dump_tenant") as dump, mock.patch(
            "control.provisioning._drop_database_and_role"
        ) as drop:
            enqueue_purge(tenant, "acme")
            self.assertEqual(process_available_jobs(), 1)
        dump.assert_not_called()
        drop.assert_called_once()
        self.assertFalse(Tenant.objects.filter(slug="acme").exists())
        self.assertFalse(Domain.objects.filter(host="acme.localhost").exists())
        self.assertFalse(ProvisionJob.objects.filter(tenant__slug="acme").exists())

    def test_purge_refuses_an_active_tenant(self):
        tenant = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.ACTIVE
        )
        with self.assertRaises(ProvisionError):
            enqueue_purge(tenant, "acme")
        self.assertTrue(Tenant.objects.filter(slug="acme").exists())

    def test_resume_missing_database_stays_suspended(self):
        tenant = Tenant.objects.create(
            name="Gone",
            slug="gone",
            status=Tenant.Status.SUSPENDED,
            suspension_reason="hold",
            db_name="tenant_gone",
        )
        with mock.patch("control.provisioning._database_exists", return_value=False):
            job = enqueue_resume(tenant)
            process_available_jobs()
        job.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.FAILED)
        self.assertIn("missing", job.error.lower())
        self.assertEqual(tenant.status, Tenant.Status.SUSPENDED)
        self.assertEqual(tenant.suspension_reason, "hold")

    def test_resume_restores_past_due_and_ignores_an_open_invoice(self):
        overdue = Tenant.objects.create(
            name="Due",
            slug="dueco",
            status=Tenant.Status.SUSPENDED,
            suspension_reason="collections",
            trial_ends_at=timezone.now() - timedelta(days=1),
        )
        _invoice(overdue, Invoice.Status.PAST_DUE)
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(overdue)
            process_available_jobs()
        overdue.refresh_from_db()
        self.assertEqual(overdue.status, Tenant.Status.PAST_DUE)
        self.assertEqual(overdue.suspension_reason, "")

        opened = Tenant.objects.create(
            name="Open",
            slug="openbill",
            status=Tenant.Status.SUSPENDED,
            suspension_reason="pause",
        )
        _invoice(opened, Invoice.Status.OPEN)
        expired = Tenant.objects.create(
            name="Old",
            slug="oldtrial",
            status=Tenant.Status.SUSPENDED,
            suspension_reason="trial over",
            trial_ends_at=timezone.now() - timedelta(days=2),
        )
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(opened)
            enqueue_resume(expired)
            process_available_jobs()
        opened.refresh_from_db()
        expired.refresh_from_db()
        self.assertEqual(opened.status, Tenant.Status.ACTIVE)
        self.assertEqual(opened.suspension_reason, "")
        self.assertEqual(expired.status, Tenant.Status.ACTIVE)
        self.assertEqual(expired.suspension_reason, "")

        live_trial = Tenant.objects.create(
            name="Trial",
            slug="trialco",
            status=Tenant.Status.SUSPENDED,
            trial_ends_at=timezone.now() + timedelta(days=4),
        )
        _invoice(live_trial, Invoice.Status.PAST_DUE)
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(live_trial)
            process_available_jobs()
        live_trial.refresh_from_db()
        self.assertEqual(live_trial.status, Tenant.Status.TRIALING)

    def test_enqueue_blocks_create_or_delete_and_not_a_queued_suspend(self):
        tenant = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.ACTIVE
        )
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.FAILED,
        )
        enqueue_suspend(tenant, "review")
        backup = enqueue_backup(tenant)
        self.assertEqual(backup.status, ProvisionJob.Status.QUEUED)

        busy = Tenant.objects.create(
            name="Beta", slug="beta", status=Tenant.Status.ACTIVE
        )
        ProvisionJob.objects.create(
            tenant=busy,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.QUEUED,
        )
        for call in (
            lambda: enqueue_suspend(busy, "no"),
            lambda: enqueue_resume(busy),
            lambda: enqueue_backup(busy),
            lambda: enqueue_migrate(busy),
            lambda: enqueue_restore(busy, "ok.dump"),
            lambda: enqueue_delete(busy, "beta"),
        ):
            with self.assertRaises(ProvisionError):
                call()

        running_delete = Tenant.objects.create(
            name="Echo", slug="echo", status=Tenant.Status.ACTIVE
        )
        ProvisionJob.objects.create(
            tenant=running_delete,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.RUNNING,
            payload={"confirm_slug": "echo"},
        )
        with self.assertRaises(ProvisionError):
            enqueue_backup(running_delete)

        deleting = Tenant.objects.create(
            name="Gamma", slug="gamma", status=Tenant.Status.DELETING
        )
        with self.assertRaises(ProvisionError):
            enqueue_backup(deleting)
        deleted = Tenant.objects.create(
            name="Delta", slug="delta", status=Tenant.Status.DELETED
        )
        with self.assertRaises(ProvisionError):
            enqueue_migrate(deleted)

        held = Tenant.objects.create(
            name="Held", slug="held", status=Tenant.Status.SUSPENDED
        )
        enqueue_resume(held)
        with self.assertRaises(ProvisionError):
            enqueue_suspend(held, "again")
        with self.assertRaises(ProvisionError):
            enqueue_resume(tenant)

        fresh = Tenant.objects.create(
            name="New", slug="newco", status=Tenant.Status.PROVISIONING
        )
        with self.assertRaises(ProvisionError):
            enqueue_suspend(fresh, "no")

    def test_startup_fails_a_stale_job_before_requeue(self):
        from io import StringIO

        from django.core.management import call_command

        tenant = Tenant.objects.create(
            name="Acme", slug="acme", status=Tenant.Status.PROVISIONING
        )
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.RUNNING,
            started_at=timezone.now() - PROVISION_STALE_AFTER - timedelta(minutes=1),
            step="migrate",
        )
        out = StringIO()
        call_command("run_provisioner", "--once", stdout=out)
        text = out.getvalue()
        self.assertIn("reclaimed=1", text)
        self.assertIn("requeued=0", text)
        self.assertIn("processed=0", text)
        job.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.FAILED)
        self.assertEqual(tenant.status, Tenant.Status.FAILED)


@override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost"],
)
class TenantDatabaseIsolationTests(TestCase):
    """Real roles on the maintenance database. No Horilla schema is migrated."""

    def setUp(self):
        super().setUp()
        self._env = _key()
        self._env.start()
        self.names = ["tenant_p3isoa", "tenant_p3isob"]
        self._drop_leftovers()

    def tearDown(self):
        self._drop_leftovers()
        self._env.stop()
        super().tearDown()

    def _drop_leftovers(self):
        with maintenance_cursor() as cursor:
            for name in self.names:
                quoted = quote_ident(name)
                cursor.execute(f"DROP DATABASE IF EXISTS {quoted} WITH (FORCE)")
                cursor.execute(f"DROP ROLE IF EXISTS {quoted}")

    def _tenant(self, slug):
        return Tenant.objects.create(
            name=slug,
            slug=slug,
            status=Tenant.Status.PROVISIONING,
        )

    def test_second_role_cannot_connect_and_create_database_is_idempotent(self):
        from django.conf import settings

        first = self._tenant("p3isoa")
        second = self._tenant("p3isob")
        for tenant in (first, second):
            job = ProvisionJob(tenant=tenant)
            _step_create_role(job)
            _step_create_database(job)
            _step_create_database(job)
            _step_revoke_public(job)
            _step_grant_connect(job)
            _step_revoke_other_roles(job)
        self.assertNotEqual(first.db_user, settings.DATABASES["default"]["USER"])
        default = settings.DATABASES["default"]
        from django.db.backends.postgresql.base import Database as PgDatabase

        second.refresh_from_db()
        with self.assertRaises(PgDatabase.OperationalError) as caught:
            PgDatabase.connect(
                host=default.get("HOST") or "db",
                port=int(default.get("PORT") or 5432),
                dbname="tenant_p3isoa",
                user="tenant_p3isob",
                password=second.db_password(),
                connect_timeout=5,
            )
        message = str(caught.exception).lower()
        self.assertIn("permission denied", message)
        self.assertNotIn(second.db_password(), str(caught.exception))

    def test_tenant_role_cannot_connect_to_the_control_database(self):
        from django.conf import settings
        from django.db.backends.postgresql.base import Database as PgDatabase

        tenant = self._tenant("p3isob")
        job = ProvisionJob(tenant=tenant)
        _step_create_role(job)
        tenant.refresh_from_db()
        default = settings.DATABASES["default"]
        control_name = default["NAME"]
        quoted = quote_ident("tenant_p3isob")
        try:
            lock_control_connect()
            with self.assertRaises(PgDatabase.OperationalError) as caught:
                PgDatabase.connect(
                    host=default.get("HOST") or "db",
                    port=int(default.get("PORT") or 5432),
                    dbname=control_name,
                    user="tenant_p3isob",
                    password=tenant.db_password(),
                    connect_timeout=5,
                )
            message = str(caught.exception).lower()
            self.assertIn("permission denied", message)
            self.assertNotIn(tenant.db_password(), str(caught.exception))
        finally:
            with maintenance_cursor() as cursor:
                cursor.execute(
                    "GRANT CONNECT ON DATABASE "
                    f"{quote_catalog_ident(control_name)} TO PUBLIC"
                )
                cursor.execute(f"DROP ROLE IF EXISTS {quoted}")
