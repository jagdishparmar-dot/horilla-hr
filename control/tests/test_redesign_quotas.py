import copy
import os
from unittest import mock

from cryptography.fernet import Fernet
from django.db import connections
from django.test import Client, TestCase, override_settings

from control.forms import TenantQuotaForm
from control.models import Invoice, Operator, OperatorAudit, Plan, ProvisionJob, Tenant
from control.provisioning import enqueue_create
from control.usage import snapshot_usage

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _point_at_test_database(alias):
    from django.conf import settings

    current = connections.settings
    if current is settings.DATABASES:
        current = current.copy()
        connections.__dict__["settings"] = current
    current[alias] = copy.deepcopy(current["default"])
    if alias in connections:
        connections[alias].close()
    return alias


@MULTI
class QuotaTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        operator = Operator(email="quota@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.operator = operator
        self.client.post(
            "/control/login/",
            {"email": "quota@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        self._env.stop()
        super().tearDown()

    def _tenant(self, slug, **kwargs):
        tenant = Tenant(
            name=slug.title(),
            slug=slug,
            status=kwargs.pop("status", Tenant.Status.ACTIVE),
            plan_fk=kwargs.pop("plan_fk", Plan.objects.get(code="starter")),
            **kwargs,
        )
        tenant.set_db_password("db-secret")
        tenant.save()
        return tenant

    def test_create_copies_seat_limit_and_storage_from_the_plan(self):
        job = enqueue_create(
            name="Growth Co",
            slug="growthco",
            plan="growth",
            seats=10,
            modules={"payroll_engine": False},
        )
        tenant = job.tenant
        self.assertEqual(tenant.seat_limit, 10)
        self.assertEqual(tenant.storage_limit_gb, 50)
        self.assertTrue(tenant.module_employee_records)
        self.assertFalse(tenant.module_payroll_engine)
        self.assertTrue(tenant.module_performance_reviews)
        self.assertEqual(job.payload["seats"], 10)

    def test_seat_limit_cannot_drop_below_the_snapshot_or_exceed_the_cap(self):
        tenant = self._tenant("capco", active_seats=10, seat_limit=25, storage_limit_gb=40)
        rejected = TenantQuotaForm(
            {
                "seat_limit": "9",
                "storage_limit_gb": "40",
                "module_employee_records": "on",
                "module_payroll_engine": "on",
                "module_performance_reviews": "on",
            },
            tenant=tenant,
        )
        self.assertFalse(rejected.is_valid())
        tenant.refresh_from_db()
        self.assertEqual(tenant.seat_limit, 25)

        accepted = TenantQuotaForm(
            {
                "seat_limit": "10",
                "storage_limit_gb": "40",
                "module_employee_records": "on",
                "module_payroll_engine": "on",
                "module_performance_reviews": "on",
            },
            tenant=tenant,
        )
        self.assertTrue(accepted.is_valid())

        over = TenantQuotaForm(
            {
                "seat_limit": "101",
                "storage_limit_gb": "40",
                "module_employee_records": "on",
                "module_payroll_engine": "on",
                "module_performance_reviews": "on",
            },
            tenant=tenant,
        )
        self.assertFalse(over.is_valid())
        tenant.refresh_from_db()
        self.assertEqual(tenant.seat_limit, 25)

    def test_save_writes_audit_and_does_not_queue_a_job(self):
        tenant = self._tenant("editco", seat_limit=25, storage_limit_gb=20, active_seats=2)
        before_jobs = ProvisionJob.objects.filter(tenant=tenant).count()
        response = self.client.post(
            "/control/tenants/editco/quota/",
            {
                "seat_limit": "40",
                "storage_limit_gb": "20",
                "module_employee_records": "on",
                "module_performance_reviews": "on",
            },
        )
        self.assertEqual(response.status_code, 302)
        tenant.refresh_from_db()
        self.assertEqual(tenant.seat_limit, 40)
        self.assertFalse(tenant.module_payroll_engine)
        self.assertEqual(ProvisionJob.objects.filter(tenant=tenant).count(), before_jobs)
        quota = OperatorAudit.objects.get(slug="editco", action=OperatorAudit.Action.QUOTA_UPDATE)
        self.assertEqual(quota.operator, self.operator)
        self.assertIn("seats 25 -> 40", quota.detail)
        module = OperatorAudit.objects.get(slug="editco", action=OperatorAudit.Action.MODULE_UPDATE)
        self.assertIn("payroll_engine True -> False", module.detail)
        reloaded = self.client.get("/control/tenants/editco/")
        self.assertContains(reloaded, "40")

    def test_seat_limit_change_issues_one_invoice(self):
        tenant = self._tenant(
            "seatco",
            seat_limit=10,
            storage_limit_gb=20,
            active_seats=1,
        )
        modules = {
            "module_employee_records": "on",
            "module_payroll_engine": "on",
            "module_performance_reviews": "on",
        }
        raised = self.client.post(
            "/control/tenants/seatco/quota/",
            {"seat_limit": "20", "storage_limit_gb": "20", **modules},
        )
        self.assertEqual(raised.status_code, 302)
        tenant.refresh_from_db()
        self.assertEqual(tenant.seat_limit, 20)
        invoice = Invoice.objects.get(tenant=tenant)
        self.assertEqual(invoice.seat_count, 20)
        self.assertTrue(
            OperatorAudit.objects.filter(
                slug="seatco", action=OperatorAudit.Action.QUOTA_UPDATE
            ).exists()
        )
        self.assertEqual(ProvisionJob.objects.filter(tenant=tenant).count(), 0)

        same = self.client.post(
            "/control/tenants/seatco/quota/",
            {"seat_limit": "20", "storage_limit_gb": "20", **modules},
        )
        self.assertEqual(same.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 1)

        storage_only = self.client.post(
            "/control/tenants/seatco/quota/",
            {"seat_limit": "20", "storage_limit_gb": "30", **modules},
        )
        self.assertEqual(storage_only.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 1)

        trial = self._tenant(
            "trialseat",
            status=Tenant.Status.TRIALING,
            seat_limit=10,
            storage_limit_gb=20,
        )
        trial_save = self.client.post(
            "/control/tenants/trialseat/quota/",
            {"seat_limit": "15", "storage_limit_gb": "20", **modules},
        )
        self.assertEqual(trial_save.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=trial).count(), 0)

    def test_directory_does_not_open_a_tenant_database(self):
        self._tenant("listed")
        with mock.patch(
            "control.usage.count_employees",
            side_effect=AssertionError("tenant database opened"),
        ):
            response = self.client.get("/control/")
        self.assertEqual(response.status_code, 200)

    def test_snapshot_reads_employee_rows_and_keeps_going_after_a_failure(self):
        alias = "tenant_quotaset"
        type(self).databases = frozenset(set(type(self).databases) | {alias})
        _point_at_test_database(alias)
        created_stub = False
        try:
            with connections[alias].cursor() as cursor:
                cursor.execute("SELECT to_regclass('public.employee_employee')")
                if cursor.fetchone()[0] is None:
                    cursor.execute(
                        "CREATE TABLE employee_employee (id integer PRIMARY KEY)"
                    )
                    created_stub = True
                cursor.execute("DELETE FROM employee_employee WHERE id IN (910001, 910002)")
                cursor.execute(
                    "INSERT INTO employee_employee (id) VALUES (910001), (910002)"
                )
            good = self._tenant("quotaok", active_seats=0)
            other = self._tenant("quotabad", active_seats=5, seat_limit=30)

            def connect(tenant):
                if tenant.slug == "quotabad":
                    raise RuntimeError("database refused")
                return alias

            errors = snapshot_usage(connect=connect)
            good.refresh_from_db()
            other.refresh_from_db()
            self.assertEqual(good.active_seats, 2)
            self.assertIsNotNone(good.usage_updated_at)
            self.assertEqual(other.active_seats, 5)
            self.assertTrue(any(line.startswith("quotabad:") for line in errors))
            self.assertNotIn("db-secret", " ".join(errors))
        finally:
            with connections[alias].cursor() as cursor:
                cursor.execute("DELETE FROM employee_employee WHERE id IN (910001, 910002)")
                if created_stub:
                    cursor.execute("DROP TABLE employee_employee")
            connections[alias].close()
