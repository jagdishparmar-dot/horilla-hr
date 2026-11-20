"""Configurable plan and add-on prices. Whole rupees, three billing cycles."""

import os
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, TestCase, override_settings

from control.models import Addon, Operator, Plan, PlanPrice, Tenant
from control.pricing import lock_subscription, quote, quote_tenant
from control.router import TenantRouter

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _operator(email="catalog@example.com"):
    operator = Operator(email=email, is_staff=True, is_active=True)
    operator.set_password("correct-horse")
    operator.save()
    return operator


@MULTI
class CatalogPriceTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator()
        self.client.post(
            "/control/login/",
            {"email": "catalog@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_seeded_cycles_match_the_locked_annual_discount(self):
        starter = PlanPrice.objects.get(plan__code="starter", cadence="monthly")
        annual = PlanPrice.objects.get(plan__code="starter", cadence="annual")
        semi = PlanPrice.objects.get(plan__code="starter", cadence="semiannual")
        self.assertEqual(starter.unit_rupees, 800)
        self.assertEqual(semi.unit_rupees, 4800)
        self.assertEqual(annual.unit_rupees, 7680)
        router = TenantRouter()
        for name in ("planprice", "addonprice"):
            self.assertFalse(router.allow_migrate("tenant_acme", "control", name))
            self.assertTrue(router.allow_migrate("default", "control", name))

    def test_semiannual_term_is_six_months_and_annual_bill_stays_11200_monthly(self):
        semi = quote("growth", "semiannual", 10, [])
        self.assertEqual(semi.term, 84000)
        self.assertEqual(semi.total_monthly, 14000)
        self.assertEqual(semi.discount, 0)
        annual = quote("growth", "annual", 10, [])
        self.assertEqual(annual.total_monthly, 11200)
        self.assertEqual(annual.term, 134400)

    def test_catalog_edit_does_not_reprice_a_locked_subscription(self):
        plan = Plan.objects.get(code="growth")
        tenant = Tenant(
            name="Locked",
            slug="lockedco",
            status=Tenant.Status.ACTIVE,
            plan_fk=plan,
            cadence=Tenant.Cadence.MONTHLY,
            seat_limit=10,
        )
        tenant.save()
        lock_subscription(tenant)
        before = quote_tenant(tenant).term
        self.assertEqual(before, 14000)
        row = PlanPrice.objects.get(plan=plan, cadence="monthly")
        row.unit_rupees = 900
        row.save(update_fields=["unit_rupees"])
        plan.monthly_price = 900
        plan.save(update_fields=["monthly_price"])
        tenant.refresh_from_db()
        self.assertEqual(quote_tenant(tenant).term, before)
        self.assertEqual(quote("growth", "monthly", 10, []).term, 9000)

    def test_operator_can_create_a_plan_and_a_negative_price_is_rejected(self):
        created = self.client.post(
            "/control/plans/new/",
            {
                "code": "pilot",
                "name": "Pilot",
                "description": "Small teams",
                "status": "active",
                "price_monthly": "500",
                "seat_cap": "20",
                "trial_days": "7",
                "setup_fee": "1000",
                "sort_order": "4",
            },
        )
        self.assertEqual(created.status_code, 302)
        plan = Plan.objects.get(code="pilot")
        self.assertEqual(plan.monthly_price, 500)
        self.assertEqual(plan.trial_days, 7)
        self.assertEqual(plan.setup_fee_rupees, 1000)
        self.assertTrue(plan.is_active)
        self.assertEqual(
            PlanPrice.objects.get(plan=plan, cadence="monthly").unit_rupees,
            500,
        )
        self.assertFalse(PlanPrice.objects.filter(plan=plan).exclude(cadence="monthly").exists())
        page = self.client.get("/control/plans/")
        self.assertContains(page, "Pilot")
        priced = quote("pilot", "monthly", 2, [])
        self.assertEqual(priced.term, 1000)
        self.assertEqual(priced.setup_fee, 1000)
        refused = self.client.post(
            "/control/plans/pilot/edit/",
            {
                "name": "Pilot",
                "description": "",
                "status": "active",
                "price_monthly": "-5",
                "trial_days": "7",
                "setup_fee": "0",
                "sort_order": "4",
            },
        )
        self.assertEqual(refused.status_code, 200)
        self.assertContains(refused, "greater than or equal to 0")
        plan.refresh_from_db()
        self.assertEqual(plan.monthly_price, 500)

    def test_inactive_plan_and_incompatible_addon_cannot_be_quoted(self):
        plan = Plan.objects.get(code="growth")
        plan.status = Plan.Status.INACTIVE
        plan.is_active = False
        plan.save(update_fields=["status", "is_active"])
        refused = self.client.post(
            "/control/plans/",
            {"plan": "growth", "cadence": "monthly", "seats": "10"},
        )
        self.assertEqual(refused.status_code, 200)
        self.assertContains(refused, "available choices")
        plan.status = Plan.Status.ACTIVE
        plan.is_active = True
        plan.save(update_fields=["status", "is_active"])
        addon = Addon.objects.get(code="audit_vault")
        addon.compatible_plans.set([Plan.objects.get(code="starter")])
        blocked = self.client.post(
            "/control/plans/",
            {
                "plan": "growth",
                "cadence": "monthly",
                "seats": "10",
                "addons": ["audit_vault"],
            },
        )
        self.assertContains(blocked, "not available on Growth")

    def test_anonymous_cannot_edit_the_catalog(self):
        anon = Client(HTTP_HOST="manage.localhost")
        response = anon.post(
            "/control/plans/new/",
            {"code": "nope", "name": "Nope", "price_monthly": "1"},
        )
        self.assertEqual(response.status_code, 302)
        self.assertIn("/control/login/", response["Location"])
        self.assertFalse(Plan.objects.filter(code="nope").exists())
