import os
from datetime import date
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, TestCase, override_settings
from django.utils import timezone

from control.metering import month_usage
from control.models import Operator, Plan, Tenant, TenantUsageDay
from control.usage import SNAPSHOT_STATUSES, record_usage_day, snapshot_usage

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


@MULTI
class UsageMeteringTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ, {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()}
        )
        self._env.start()
        self.addCleanup(self._env.stop)

    def _tenant(self, slug, status=Tenant.Status.ACTIVE):
        tenant = Tenant(
            name=slug.title(),
            slug=slug,
            status=status,
            plan_fk=Plan.objects.get(code="starter"),
        )
        tenant.set_db_password("db-secret")
        tenant.save()
        return tenant

    def _day(self, tenant, day, active, archived=0):
        return TenantUsageDay.objects.create(
            tenant=tenant, day=day, active_employees=active, archived_employees=archived
        )

    def test_month_bills_the_peak_not_the_last_or_average_reading(self):
        tenant = self._tenant("peakco")
        self._day(tenant, date(2026, 10, 1), 20)
        self._day(tenant, date(2026, 10, 12), 31)
        self._day(tenant, date(2026, 10, 30), 24)
        usage = month_usage(tenant, 2026, 10)
        self.assertEqual(usage.billable, 31)
        self.assertEqual(usage.latest, 24)
        self.assertEqual(usage.readings, 3)
        self.assertEqual(usage.days_in_month, 31)
        self.assertFalse(usage.is_complete)
        self.assertEqual(usage.first_day, date(2026, 10, 1))
        self.assertEqual(usage.last_day, date(2026, 10, 30))

    def test_month_ignores_other_months_and_other_tenants(self):
        tenant = self._tenant("monthco")
        other = self._tenant("otherco")
        self._day(tenant, date(2026, 9, 30), 99)
        self._day(tenant, date(2026, 11, 1), 98)
        self._day(other, date(2026, 10, 5), 97)
        self._day(tenant, date(2026, 10, 5), 7)
        self.assertEqual(month_usage(tenant, 2026, 10).billable, 7)

    def test_month_without_readings_is_none_not_zero(self):
        tenant = self._tenant("emptyco")
        self.assertIsNone(month_usage(tenant, 2026, 10))

    def test_a_month_with_every_day_read_is_complete(self):
        tenant = self._tenant("fullco")
        for day in range(1, 31):
            self._day(tenant, date(2026, 11, day), 5)
        self.assertTrue(month_usage(tenant, 2026, 11).is_complete)

    def test_same_day_keeps_the_highest_reading_but_latest_archived_count(self):
        tenant = self._tenant("sameday")
        today = timezone.localdate()
        record_usage_day(tenant, 12, 1, day=today)
        record_usage_day(tenant, 9, 4, day=today)
        row = TenantUsageDay.objects.get(tenant=tenant, day=today)
        self.assertEqual(row.active_employees, 12)
        self.assertEqual(row.archived_employees, 4)
        record_usage_day(tenant, 15, 4, day=today)
        row.refresh_from_db()
        self.assertEqual(row.active_employees, 15)
        self.assertEqual(TenantUsageDay.objects.filter(tenant=tenant).count(), 1)

    def test_past_due_tenants_are_measured_and_suspended_ones_are_not(self):
        self.assertIn("past_due", SNAPSHOT_STATUSES)
        self.assertNotIn("suspended", SNAPSHOT_STATUSES)
        self._tenant("duebill", status=Tenant.Status.PAST_DUE)
        self._tenant("pausedco", status=Tenant.Status.SUSPENDED)
        seen = []

        def connect(tenant):
            seen.append(tenant.slug)
            raise RuntimeError("stop here")

        snapshot_usage(connect=connect)
        self.assertIn("duebill", seen)
        self.assertNotIn("pausedco", seen)

    def test_tenant_page_shows_billable_employees_by_month(self):
        operator = Operator(email="meter@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        client = Client(HTTP_HOST="manage.localhost")
        client.post(
            "/control/login/",
            {"email": "meter@example.com", "password": "correct-horse"},
        )
        tenant = self._tenant("pagebill")
        self._day(tenant, timezone.localdate(), 17)
        response = client.get("/control/tenants/pagebill/")
        self.assertEqual(response.status_code, 200)
        self.assertContains(response, "Billable employees")
        self.assertContains(response, "(so far)")
        self.assertContains(response, "No readings")
        rows = response.context["billing_months"]
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["usage"].billable, 17)
        self.assertIsNone(rows[1]["usage"])
