import os
from unittest import mock

from cryptography.fernet import Fernet
from django.apps import apps
from django.test import Client, TestCase, override_settings

from control.catalog import plan_code_for_label, seed_catalog
from control.models import Addon, Plan, Tenant, TenantAddon
from control.pricing import quote
from control.router import TenantRouter

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


@MULTI
class CatalogAndQuoteTests(TestCase):
    def test_seed_is_idempotent_and_starter_is_800(self):
        seed_catalog(apps)
        seed_catalog(apps)
        self.assertEqual(Plan.objects.count(), 4)
        self.assertEqual(Addon.objects.count(), 4)
        starter = Plan.objects.get(code="starter")
        self.assertEqual(starter.monthly_price, 800)
        self.assertEqual(starter.seat_cap, 100)
        self.assertFalse(hasattr(starter, "storage_gb_per_seat"))
        enterprise = Plan.objects.get(code="enterprise")
        self.assertIsNone(enterprise.seat_cap)
        self.assertTrue(enterprise.contact_sales)
        self.assertFalse(starter.contact_sales)
        self.assertTrue(Addon.objects.get(code="calibration_360").per_seat)
        self.assertFalse(Addon.objects.get(code="priority_sla").per_seat)
        self.assertEqual(Addon.objects.get(code="multi_state_tax").amount, 18000)

    def test_growth_annual_ten_seats_is_11200(self):
        priced = quote("growth", "annual", 10, [])
        self.assertEqual(priced.base_monthly, 14000)
        self.assertEqual(priced.discount, 2800)
        self.assertEqual(priced.addon_monthly, 0)
        self.assertEqual(priced.total_monthly, 11200)
        self.assertEqual(priced.annual, 134400)

    def test_annual_discount_covers_one_flat_and_one_per_seat_addon(self):
        priced = quote(
            "growth",
            "annual",
            10,
            ["multi_state_tax", "calibration_360"],
        )
        self.assertEqual(priced.base_monthly, 14000)
        self.assertEqual(priced.discount, 7000)
        self.assertEqual(priced.addon_monthly, 16800)
        self.assertEqual(priced.total_monthly, 28000)
        self.assertEqual(priced.annual, 336000)
        monthly = quote("growth", "monthly", 10, ["multi_state_tax", "calibration_360"])
        self.assertEqual(monthly.discount, 0)
        self.assertEqual(monthly.addon_monthly, 21000)
        self.assertEqual(monthly.total_monthly, 35000)

    def test_label_mapping_and_live_slugs_are_not_required_here(self):
        self.assertEqual(plan_code_for_label("Growth"), "growth")
        self.assertEqual(plan_code_for_label(" standard "), "unassigned")
        self.assertEqual(plan_code_for_label(""), "unassigned")
        self.assertEqual(plan_code_for_label(None), "unassigned")

    def test_tenant_can_subscribe_to_growth_annual_and_one_addon(self):
        tenant = Tenant(name="Quoted", slug="quoted", status=Tenant.Status.ACTIVE)
        tenant.plan_fk = Plan.objects.get(code="growth")
        tenant.cadence = Tenant.Cadence.ANNUAL
        tenant.save()
        addon = Addon.objects.get(code="audit_vault")
        tenant.addons.add(addon)
        self.assertEqual(tenant.plan_fk.code, "growth")
        self.assertEqual(tenant.cadence, "annual")
        self.assertEqual(list(tenant.addons.values_list("code", flat=True)), ["audit_vault"])
        self.assertEqual(TenantAddon.objects.filter(tenant=tenant).count(), 1)

    def test_control_catalog_does_not_migrate_into_a_tenant_database(self):
        router = TenantRouter()
        for model_name in ("plan", "addon", "tenantaddon"):
            self.assertFalse(router.allow_migrate("tenant_acme", "control", model_name))
            self.assertTrue(router.allow_migrate("default", "control", model_name))


@MULTI
class PlansPageTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        from control.models import Operator

        operator = Operator(email="plans@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.client.post(
            "/control/login/",
            {"email": "plans@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_plans_page_quotes_on_post_and_hides_unassigned(self):
        page = self.client.get("/control/plans/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Starter")
        self.assertContains(page, "₹800")
        self.assertContains(page, "₹1,400")
        self.assertContains(page, "₹2,200")
        self.assertContains(page, "₹14,000")
        self.assertContains(page, "per active employee / month")
        self.assertNotContains(page, ">Unassigned<")
        self.assertNotContains(page, "Semi-annual")
        self.assertNotContains(page, "Storage")
        self.assertNotContains(page, 'name="cadence"')

        monthly = self.client.post(
            "/control/plans/",
            {"plan": "growth", "seats": "10"},
        )
        self.assertEqual(monthly.status_code, 200)
        self.assertContains(monthly, "₹14,000")
        self.assertContains(monthly, "₹1,68,000")
        self.assertNotContains(monthly, "₹11,200")

    def test_create_form_rejects_an_unknown_plan_and_stores_the_catalog_choice(self):
        unknown = self.client.post(
            "/control/tenants/new/",
            {
                "name": "Nope",
                "slug": "nope",
                "plan": "standard",
                "cadence": "monthly",
                "seats": "10",
            },
        )
        self.assertEqual(unknown.status_code, 200)
        self.assertContains(unknown, "not one of the available choices")
        self.assertFalse(Tenant.objects.filter(slug="nope").exists())

        with mock.patch(
            "control.provisioning.maintenance_cursor",
            side_effect=AssertionError("create database during the request"),
        ):
            created = self.client.post(
                "/control/tenants/new/",
                {
                    "name": "Quoted Co",
                    "slug": "quotedco",
                    "plan": "growth",
                    "seats": "10",
                },
            )
        self.assertEqual(created.status_code, 302)
        tenant = Tenant.objects.get(slug="quotedco")
        self.assertEqual(tenant.plan_fk.code, "growth")
        self.assertEqual(tenant.cadence, "monthly")
        job = tenant.jobs.get()
        self.assertEqual(job.status, "queued")
        self.assertEqual(job.payload["seats"], 10)
        self.assertEqual(job.payload["plan"], "growth")
