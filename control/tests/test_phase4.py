import json
import os
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, RequestFactory, TestCase, override_settings
from django.utils import timezone

from control.auth import session_cookie_name
from control.models import Domain, Operator, OperatorAudit, ProvisionJob, Tenant
from control.provisioning import enqueue_backup, process_available_jobs

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)
PASSWORD = "temporary-secret"


def _operator(email, password="correct-horse", *, staff=True, active=True):
    operator = Operator(email=email, is_staff=staff, is_active=active)
    operator.set_password(password)
    operator.save()
    return operator


@MULTI
class DashboardTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("ops@example.com")

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def _login(self, email="ops@example.com", password="correct-horse"):
        return self.client.post(
            "/control/login/",
            {"email": email, "password": password},
        )

    def test_session_cookie_name_is_separate_on_the_dashboard(self):
        request = RequestFactory().get("/control/")
        request.control_plane = False
        self.assertEqual(session_cookie_name(request), "sessionid")
        request.control_plane = True
        self.assertEqual(session_cookie_name(request), "control_sessionid")

    def test_login_logout_and_inactive_operator(self):
        inactive = _operator("old@example.com", active=False)
        failed = self.client.post(
            "/control/login/",
            {"email": inactive.email, "password": "correct-horse"},
        )
        self.assertEqual(failed.status_code, 200)
        self.assertNotIn("control_sessionid", failed.cookies)
        self.assertContains(failed, "not valid")

        wrong = self._login(password="nope-nope-nope")
        self.assertEqual(wrong.status_code, 200)
        self.assertNotIn("control_sessionid", wrong.cookies)

        response = self._login()
        self.assertEqual(response.status_code, 302)
        self.assertIn("control_sessionid", response.cookies)
        self.assertNotIn("sessionid", response.cookies)
        self.assertEqual(response.cookies["control_sessionid"]["httponly"], True)

        home = self.client.get("/control/")
        self.assertEqual(home.status_code, 200)
        self.assertContains(home, "Tenants")

        logged_out = self.client.post("/control/logout/")
        self.assertEqual(logged_out.status_code, 302)
        self.assertEqual(logged_out.cookies["control_sessionid"].value, "")
        self.assertEqual(self.client.get("/control/").status_code, 302)

    def test_create_queues_a_job_and_duplicate_slug_is_a_form_error(self):
        self._login()
        payload = {
            "name": "Acme",
            "slug": "Acme",
            "admin_name": "Ada",
            "admin_email": "ada@acme.test",
            "admin_password": PASSWORD,
            "plan": "standard",
        }
        with mock.patch(
            "control.provisioning.maintenance_cursor",
            side_effect=AssertionError("create database during the request"),
        ):
            created = self.client.post("/control/tenants/new/", payload)
        self.assertEqual(created.status_code, 302)
        self.assertEqual(created.url, "/control/tenants/acme/")
        tenant = Tenant.objects.get(slug="acme")
        self.assertEqual(tenant.status, Tenant.Status.PROVISIONING)
        job = tenant.jobs.get()
        self.assertEqual(job.status, ProvisionJob.Status.QUEUED)
        self.assertEqual(job.kind, ProvisionJob.Kind.CREATE)
        self.assertNotIn(PASSWORD, json.dumps(job.payload))
        self.assertNotIn(PASSWORD, created.url)
        audit = OperatorAudit.objects.get(slug="acme")
        self.assertEqual(audit.action, OperatorAudit.Action.CREATE)
        self.assertEqual(audit.operator, self.operator)
        self.assertNotIn(PASSWORD, audit.detail)
        self.assertNotIn(PASSWORD, str(audit))

        again = self.client.post("/control/tenants/new/", payload)
        self.assertEqual(again.status_code, 200)
        self.assertContains(again, "already exists")
        self.assertEqual(Tenant.objects.filter(slug="acme").count(), 1)

        reserved = self.client.post(
            "/control/tenants/new/",
            {**payload, "slug": "public"},
        )
        self.assertEqual(reserved.status_code, 200)
        self.assertContains(reserved, "reserved")

    def test_list_shows_registry_fields_without_a_tenant_query(self):
        tenant = Tenant.objects.create(name="Acme", slug="acme", status=Tenant.Status.ACTIVE)
        Domain.objects.create(
            tenant=tenant, host="acme.localhost", is_primary=True, verified=True
        )
        ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
            finished_at=timezone.now(),
            step="dump",
        )
        self._login()
        with mock.patch(
            "control.db.ensure_tenant_connection",
            side_effect=AssertionError("tenant database opened"),
        ):
            page = self.client.get("/control/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Acme")
        self.assertContains(page, "acme")
        self.assertContains(page, "acme.localhost")
        self.assertContains(page, "active")
        self.assertContains(page, "backup succeeded")

    def test_actions_enqueue_jobs_and_delete_requires_the_slug(self):
        tenant = Tenant.objects.create(name="Acme", slug="acme", status=Tenant.Status.ACTIVE)
        job = ProvisionJob.objects.create(
            tenant=tenant,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.FAILED,
            step="migrate",
            error="migrate failed",
        )
        self._login()
        detail = self.client.get("/control/tenants/acme/")
        self.assertContains(detail, "migrate")
        self.assertContains(detail, "migrate failed")
        self.assertNotContains(detail, "payload")

        with mock.patch(
            "control.provisioning.maintenance_cursor",
            side_effect=AssertionError("sql from the dashboard"),
        ):
            suspended = self.client.post("/control/tenants/acme/suspend/")
            backed_up = self.client.post("/control/tenants/acme/backup/")
            migrated = self.client.post("/control/tenants/acme/migrate/")
            restored = self.client.post(
                "/control/tenants/acme/restore/",
                {"dump_name": "../secret.dump"},
            )
            mismatch = self.client.post(
                "/control/tenants/acme/delete/",
                {"confirm_slug": "nope"},
            )
        self.assertEqual(suspended.status_code, 302)
        self.assertEqual(backed_up.status_code, 302)
        self.assertEqual(migrated.status_code, 302)
        self.assertEqual(restored.status_code, 200)
        self.assertContains(restored, "not valid")
        self.assertContains(mismatch, "Type the tenant slug", status_code=400)
        self.assertFalse(
            tenant.jobs.filter(kind=ProvisionJob.Kind.DELETE).exists()
        )
        self.assertFalse(
            tenant.jobs.filter(kind=ProvisionJob.Kind.RESTORE).exists()
        )
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)

        deleted = self.client.post(
            "/control/tenants/acme/delete/",
            {"confirm_slug": "acme"},
        )
        self.assertEqual(deleted.status_code, 302)
        queued = tenant.jobs.get(kind=ProvisionJob.Kind.DELETE)
        self.assertEqual(queued.status, ProvisionJob.Status.QUEUED)
        self.assertEqual(
            set(
                OperatorAudit.objects.filter(slug="acme").values_list("action", flat=True)
            ),
            {
                OperatorAudit.Action.SUSPEND,
                OperatorAudit.Action.BACKUP,
                OperatorAudit.Action.MIGRATE,
                OperatorAudit.Action.DELETE,
            },
        )
        for row in OperatorAudit.objects.all():
            self.assertNotIn(PASSWORD, row.detail)
            self.assertNotIn("secret", row.detail)
        job.refresh_from_db()
        self.assertEqual(job.status, ProvisionJob.Status.FAILED)
        queued.refresh_from_db()
        self.assertEqual(queued.status, ProvisionJob.Status.QUEUED)

    def test_backup_stays_queued_while_another_job_runs(self):
        tenant = Tenant.objects.create(name="Acme", slug="acme", status=Tenant.Status.ACTIVE)
        from control.provisioning import enqueue_suspend

        enqueue_suspend(tenant)
        backup = enqueue_backup(tenant)
        self.assertEqual(process_available_jobs(), 1)
        backup.refresh_from_db()
        self.assertEqual(backup.status, ProvisionJob.Status.QUEUED)
        self.assertEqual(
            tenant.jobs.get(kind=ProvisionJob.Kind.SUSPEND).status,
            ProvisionJob.Status.SUCCEEDED,
        )

    def test_operator_management(self):
        self._login()
        created = self.client.post(
            "/control/operators/",
            {
                "email": "clerk@example.com",
                "password": PASSWORD,
                "is_staff": "",
            },
        )
        self.assertEqual(created.status_code, 302)
        clerk = Operator.objects.get(email="clerk@example.com")
        self.assertFalse(clerk.is_staff)
        audit = OperatorAudit.objects.get(action=OperatorAudit.Action.OPERATOR_CREATE)
        self.assertIn("clerk@example.com", audit.detail)
        self.assertNotIn(PASSWORD, audit.detail)

        self.client.post("/control/logout/")
        self.client.post(
            "/control/login/",
            {"email": "clerk@example.com", "password": PASSWORD},
        )
        forbidden = self.client.get("/control/operators/")
        self.assertEqual(forbidden.status_code, 403)
        self.assertEqual(self.client.get("/control/").status_code, 200)

        self.client.post("/control/logout/")
        self._login()
        blocked = self.client.post(f"/control/operators/{self.operator.pk}/deactivate/")
        self.assertEqual(blocked.status_code, 403)
        self.operator.refresh_from_db()
        self.assertTrue(self.operator.is_active)

        other = _operator("second@example.com")
        removed = self.client.post(f"/control/operators/{other.pk}/deactivate/")
        self.assertEqual(removed.status_code, 302)
        other.refresh_from_db()
        self.assertFalse(other.is_active)
        self.client.post("/control/logout/")
        denied = self.client.post(
            "/control/login/",
            {"email": "second@example.com", "password": "correct-horse"},
        )
        self.assertEqual(denied.status_code, 200)
        self.assertContains(denied, "not valid")
        self.assertEqual(self.client.get("/control/").status_code, 302)
        row = OperatorAudit.objects.get(action=OperatorAudit.Action.OPERATOR_DEACTIVATE)
        self.assertIn("second@example.com", row.detail)
        self.assertNotIn("correct-horse", row.detail)
