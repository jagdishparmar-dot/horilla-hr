"""Plan features, bundled add-ons, Talk to Sales, and monthly-only pricing."""

import os
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, TestCase, override_settings

from control.models import (
    Addon,
    Operator,
    OperatorAudit,
    Plan,
    PlanFeature,
    PlanPrice,
    Tenant,
    TenantAddon,
)
from control.pricing import lock_subscription, quote, quote_tenant

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _plan_payload(**extra):
    data = {
        "code": "pilot",
        "name": "Pilot",
        "description": "Small teams",
        "status": "active",
        "price_monthly": "500",
        "seat_cap": "20",
        "features": "",
        "trial_days": "7",
        "setup_fee": "0",
        "sort_order": "4",
    }
    data.update(extra)
    return data


@MULTI
class PlanCatalogTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        operator = Operator(email="feat@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.client.post(
            "/control/login/",
            {"email": "feat@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_plan_form_has_no_storage_or_billing_cycle_fields(self):
        page = self.client.get("/control/plans/new/")
        self.assertEqual(page.status_code, 200)
        for gone in ("storage", "Storage", "price_semiannual", "price_annual", "Semi-annual"):
            self.assertNotContains(page, gone)
        self.assertContains(page, "Price per active employee / month")
        self.assertContains(page, 'name="features"')
        self.assertContains(page, 'name="contact_sales"')
        self.assertContains(page, 'name="included_addons"')

    def test_addon_form_prices_monthly_only(self):
        page = self.client.get("/control/plans/addons/new/")
        self.assertContains(page, 'name="price_monthly"')
        self.assertNotContains(page, "price_semiannual")
        self.assertNotContains(page, "price_annual")

    def test_features_are_cleaned_ordered_and_replaced_on_edit(self):
        created = self.client.post(
            "/control/plans/new/",
            _plan_payload(
                features="  Unlimited leave policies \n\nPayroll   with statutory reports\nunlimited leave policies\n"
            ),
        )
        self.assertEqual(created.status_code, 302)
        plan = Plan.objects.get(code="pilot")
        self.assertEqual(
            list(plan.features.values_list("text", flat=True)),
            ["Unlimited leave policies", "Payroll with statutory reports"],
        )

        edit = self.client.get("/control/plans/pilot/edit/")
        self.assertContains(edit, "Unlimited leave policies\nPayroll with statutory reports")

        saved = self.client.post(
            "/control/plans/pilot/edit/",
            _plan_payload(features="Mobile app\nUnlimited leave policies"),
        )
        self.assertEqual(saved.status_code, 302)
        self.assertEqual(
            list(plan.features.values_list("text", flat=True)),
            ["Mobile app", "Unlimited leave policies"],
        )

        cleared = self.client.post("/control/plans/pilot/edit/", _plan_payload(features=""))
        self.assertEqual(cleared.status_code, 302)
        self.assertFalse(plan.features.exists())

    def test_too_many_or_too_long_features_are_refused(self):
        many = "\n".join(f"Feature {n}" for n in range(21))
        refused = self.client.post("/control/plans/new/", _plan_payload(features=many))
        self.assertEqual(refused.status_code, 200)
        self.assertContains(refused, "up to 20 features")
        self.assertFalse(Plan.objects.filter(code="pilot").exists())

        long_line = self.client.post("/control/plans/new/", _plan_payload(features="x" * 161))
        self.assertEqual(long_line.status_code, 200)
        self.assertContains(long_line, "under 160 characters")
        self.assertFalse(Plan.objects.filter(code="pilot").exists())

    def test_talk_to_sales_and_included_addons_are_saved_and_audited(self):
        vault = Addon.objects.get(code="audit_vault")
        created = self.client.post(
            "/control/plans/new/",
            _plan_payload(
                contact_sales="on",
                included_addons=[str(vault.pk)],
                features="Dedicated success manager",
            ),
        )
        self.assertEqual(created.status_code, 302)
        plan = Plan.objects.get(code="pilot")
        self.assertTrue(plan.contact_sales)
        self.assertEqual(list(plan.included_addons.all()), [vault])
        row = OperatorAudit.objects.filter(action=OperatorAudit.Action.CATALOG_UPDATE).latest("pk")
        self.assertIn("monthly 500", row.detail)
        self.assertIn("talk to sales", row.detail)
        self.assertIn("features 1", row.detail)
        self.assertIn("includes audit_vault", row.detail)

        self.client.post("/control/plans/pilot/edit/", _plan_payload())
        plan.refresh_from_db()
        self.assertFalse(plan.contact_sales)
        self.assertFalse(plan.included_addons.exists())

    def test_saving_a_plan_writes_only_the_monthly_price_row(self):
        self.client.post("/control/plans/new/", _plan_payload())
        plan = Plan.objects.get(code="pilot")
        self.assertEqual(
            list(PlanPrice.objects.filter(plan=plan).values_list("cadence", "unit_rupees")),
            [("monthly", 500)],
        )

    def test_plans_page_shows_features_talk_to_sales_and_included_addons(self):
        starter = Plan.objects.get(code="starter")
        PlanFeature.objects.create(plan=starter, text="Unlimited leave policies", sort_order=0)
        starter.included_addons.add(Addon.objects.get(code="priority_sla"))
        page = self.client.get("/control/plans/")
        self.assertContains(page, "Unlimited leave policies")
        self.assertContains(page, "Priority SLA")
        self.assertContains(page, "Talk to Sales")
        self.assertContains(page, "per active employee / month")
        self.assertNotContains(page, "Storage")
        self.assertNotContains(page, "GB / seat")

    def test_a_bundled_addon_is_free_in_a_quote(self):
        starter = Plan.objects.get(code="starter")
        starter.included_addons.add(Addon.objects.get(code="priority_sla"))
        bundled = quote(starter, "monthly", 10, ["priority_sla"])
        plain = quote(starter, "monthly", 10, [])
        self.assertEqual(bundled.total_monthly, plain.total_monthly)
        self.assertEqual(bundled.addon_monthly, 0)
        paid = quote(starter, "monthly", 10, ["audit_vault"])
        self.assertEqual(paid.addon_monthly, 14000)

    def test_quote_form_adds_bundled_addons_and_keeps_them_free(self):
        starter = Plan.objects.get(code="starter")
        starter.included_addons.add(Addon.objects.get(code="priority_sla"))
        page = self.client.post("/control/plans/", {"plan": "starter", "seats": "10"})
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "₹8,000")
        self.assertNotContains(page, "₹34,000")

    def test_provision_form_lists_addons_and_attaches_bundled_ones_free(self):
        growth = Plan.objects.get(code="growth")
        growth.included_addons.add(Addon.objects.get(code="priority_sla"))
        form = self.client.get("/control/tenants/new/")
        self.assertContains(form, 'name="addons"')
        self.assertNotContains(form, 'name="cadence"')
        created = self.client.post(
            "/control/tenants/new/",
            {
                "name": "Bundle Co",
                "slug": "bundleco",
                "plan": "growth",
                "seats": "10",
                "addons": ["audit_vault"],
                "module_employee_records": "on",
            },
        )
        self.assertEqual(created.status_code, 302)
        tenant = Tenant.objects.get(slug="bundleco")
        self.assertEqual(tenant.cadence, "monthly")
        self.assertEqual(tenant.storage_limit_gb, 0)
        self.assertEqual(
            sorted(tenant.addons.values_list("code", flat=True)),
            ["audit_vault", "priority_sla"],
        )
        locked = {
            link.addon.code: link.locked_unit
            for link in TenantAddon.objects.filter(tenant=tenant).select_related("addon")
        }
        self.assertEqual(locked, {"audit_vault": 14000, "priority_sla": 0})
        self.assertEqual(quote_tenant(tenant).total_monthly, 10 * 1400 + 14000)

    def test_a_bundled_addon_cannot_be_dropped_from_a_subscription(self):
        starter = Plan.objects.get(code="starter")
        starter.included_addons.add(Addon.objects.get(code="priority_sla"))
        tenant = Tenant(
            name="Sub Co",
            slug="subco",
            status=Tenant.Status.ACTIVE,
            plan_fk=Plan.objects.get(code="growth"),
            seat_limit=10,
        )
        tenant.save()
        saved = self.client.post(
            "/control/tenants/subco/subscription/",
            {"plan": "starter", "addons": ["audit_vault"]},
        )
        self.assertEqual(saved.status_code, 302)
        tenant.refresh_from_db()
        self.assertEqual(
            sorted(tenant.addons.values_list("code", flat=True)),
            ["audit_vault", "priority_sla"],
        )
        self.assertEqual(quote_tenant(tenant).addon_monthly, 14000)

    def test_saving_the_subscription_moves_an_annual_tenant_to_monthly(self):
        tenant = Tenant(
            name="Old Co",
            slug="oldco",
            status=Tenant.Status.ACTIVE,
            plan_fk=Plan.objects.get(code="growth"),
            cadence=Tenant.Cadence.ANNUAL,
            seat_limit=10,
        )
        tenant.save()
        lock_subscription(tenant)
        self.assertEqual(quote_tenant(tenant).total_monthly, 11200)
        saved = self.client.post("/control/tenants/oldco/subscription/", {"plan": "growth"})
        self.assertEqual(saved.status_code, 302)
        tenant.refresh_from_db()
        self.assertEqual(tenant.cadence, "monthly")
        self.assertEqual(tenant.locked_plan_unit, 1400)
        self.assertEqual(quote_tenant(tenant).total_monthly, 14000)

    def test_an_existing_annual_tenant_still_prices_from_its_locked_unit(self):
        tenant = Tenant(
            name="Locked Co",
            slug="lockedannual",
            status=Tenant.Status.ACTIVE,
            plan_fk=Plan.objects.get(code="growth"),
            cadence=Tenant.Cadence.ANNUAL,
            seat_limit=10,
        )
        tenant.save()
        lock_subscription(tenant)
        self.assertEqual(quote_tenant(tenant).term, 134400)
