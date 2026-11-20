"""Public site on the apex host, and operator review of workspace requests."""

import os
from unittest import mock

from cryptography.fernet import Fernet
from django.core.cache import cache
from django.db import connection
from django.http import HttpResponse, HttpResponseNotFound
from django.test import Client, RequestFactory, TestCase, override_settings
from django.test.utils import CaptureQueriesContext
from django.urls import Resolver404, resolve

from control.context import get_tenant_alias
from control.hosts import platform_csrf_origins
from control.middleware import TenantMiddleware
from control.models import Domain, Operator, OperatorAudit, Plan, Tenant, WorkspaceRequest
from control.router import TenantRouter
from horilla.isolation import activate_cache_scope, clear_cache_scope

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    HORILLA_LEGACY_HOST_REDIRECT="",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _payload(slug="northwind", **extra):
    data = {
        "company_name": "Northwind",
        "contact_name": "Ada Lovelace",
        "email": "ada@northwind.test",
        "phone": "555",
        "slug": slug,
        "plan": "",
        "seat_count": "20",
        "message": "Please set up a workspace.",
    }
    data.update(extra)
    return data


def _clear_request_limit():
    token = activate_cache_scope("marketing")
    try:
        cache.delete("marketing-request:127.0.0.1")
    finally:
        clear_cache_scope(token)


@MULTI
class MarketingSiteTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        _clear_request_limit()
        self.public = Client(HTTP_HOST="localhost")
        self.operator = Operator(email="ops@example.com", is_staff=True, is_active=True)
        self.operator.set_password("correct-horse")
        self.operator.save()
        self.acme = Tenant(name="Acme", slug="acme", status=Tenant.Status.ACTIVE)
        self.acme.set_db_password("s3cret-db")
        self.acme.save()
        Domain.objects.create(
            tenant=self.acme,
            host="acme.localhost",
            is_primary=True,
            verified=True,
        )
        paused = Tenant(name="Paused", slug="paused", status=Tenant.Status.SUSPENDED)
        paused.save()
        Domain.objects.create(
            tenant=paused,
            host="paused.localhost",
            is_primary=True,
            verified=True,
        )

    def tearDown(self):
        from django.db import connections

        from control.context import clear_tenant_alias

        clear_tenant_alias()
        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        self._env.stop()
        super().tearDown()

    def test_apex_pages_do_not_open_a_tenant(self):
        for path in ("/", "/features/", "/pricing/", "/request/"):
            response = self.public.get(path)
            self.assertEqual(response.status_code, 200, path)
            self.assertIsNone(get_tenant_alias())
        self.assertContains(self.public.get("/"), "Mondays back")
        self.assertContains(self.public.get("/pricing/"), "Starter")
        self.assertContains(self.public.get("/pricing/"), "₹800")
        self.assertContains(self.public.get("/pricing/"), "exclusive of GST")
        self.assertNotContains(self.public.get("/pricing/"), "Unassigned")

    def test_mobile_app_section_is_coming_soon_with_no_store_links(self):
        page = self.public.get("/")
        self.assertContains(page, 'id="mobile-app"')
        self.assertContains(page, "Google Play")
        self.assertContains(page, "App Store")
        self.assertContains(page, "Coming soon", count=2)
        self.assertContains(page, "marketing/app-feature.png")
        body = page.content.decode().lower()
        self.assertNotIn("play.google.com", body)
        self.assertNotIn("apps.apple.com", body)

    def test_public_pages_never_link_to_the_operator_dashboard(self):
        for path in (
            "/",
            "/features/",
            "/pricing/",
            "/sign-in/",
            "/request/",
            "/request/sent/",
            "/contact-sales/",
            "/contact-sales/sent/",
        ):
            body = self.public.get(path).content.decode().lower()
            self.assertNotIn("operators", body, path)
            self.assertNotIn("manage.localhost", body, path)
            self.assertNotIn("/control/", body, path)

    def test_sign_in_page_renders_the_lookup_form(self):
        page = self.public.get("/sign-in/")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Find your workspace")
        self.assertContains(page, 'name="slug"')

    def test_features_page_lists_every_module(self):
        from marketing.content import MODULES

        page = self.public.get("/features/")
        self.assertEqual(len(MODULES), 9)
        for module in MODULES:
            self.assertContains(page, f'id="{module["key"]}"')
            self.assertContains(page, module["name"])

    def test_pricing_is_monthly_per_active_employee_with_no_storage(self):
        for path in ("/", "/pricing/"):
            page = self.public.get(path)
            self.assertContains(page, "₹800", msg_prefix=path)
            self.assertContains(page, "per active employee / month", msg_prefix=path)
            self.assertContains(page, "?plan=starter", msg_prefix=path)
            self.assertNotContains(page, "Unassigned", msg_prefix=path)
            body = page.content.decode()
            for gone in ("cycle-annual", "Every 6 months", "Semi-annual", "GB storage", "Storage per seat"):
                self.assertNotIn(gone, body, f"{path}: {gone}")
        # Starter's old annual price (₹640 a month) must not come back.
        self.assertNotContains(self.public.get("/pricing/"), "₹640")

    def test_a_talk_to_sales_plan_shows_no_price_and_links_to_the_sales_form(self):
        enterprise = Plan.objects.get(code="enterprise")
        self.assertTrue(enterprise.contact_sales)
        self.assertEqual(enterprise.monthly_price, 2200)
        for path in ("/", "/pricing/"):
            page = self.public.get(path)
            self.assertNotContains(page, "₹2,200", msg_prefix=path)
            self.assertContains(page, "Custom pricing", msg_prefix=path)
            self.assertContains(page, "/contact-sales/?plan=enterprise", msg_prefix=path)
            self.assertNotContains(page, "?plan=enterprise\">Request", msg_prefix=path)
        # The listed plans keep a price and the normal request link.
        self.assertContains(self.public.get("/pricing/"), "₹1,400")

    def test_a_talk_to_sales_plan_hides_its_setup_fee_too(self):
        Plan.objects.filter(code="enterprise").update(setup_fee_rupees=50000)
        page = self.public.get("/pricing/")
        self.assertNotContains(page, "₹50,000")
        self.assertContains(page, "Quoted by sales")

    def test_plan_features_and_included_addons_appear_on_the_plan_card(self):
        from control.models import Addon, PlanFeature

        starter = Plan.objects.get(code="starter")
        PlanFeature.objects.create(plan=starter, text="Unlimited leave policies", sort_order=0)
        PlanFeature.objects.create(plan=starter, text="Payroll with statutory reports", sort_order=1)
        starter.included_addons.add(Addon.objects.get(code="audit_vault"))
        page = self.public.get("/pricing/")
        self.assertContains(page, "Unlimited leave policies")
        self.assertContains(page, "Payroll with statutory reports")
        self.assertContains(page, "Dedicated Compliance Vault included")
        body = page.content.decode()
        self.assertLess(body.index("Unlimited leave policies"), body.index("Payroll with statutory reports"))

    def test_the_sales_form_saves_an_enquiry_for_operators_and_provisions_nothing(self):
        enterprise = Plan.objects.get(code="enterprise")
        page = self.public.get("/contact-sales/?plan=enterprise")
        self.assertEqual(page.status_code, 200)
        self.assertContains(page, "Talk to Sales")
        self.assertContains(page, f'<option value="{enterprise.pk}" selected>Enterprise</option>', html=True)
        self.assertNotContains(page, 'name="slug"')
        before = Tenant.objects.count()
        sent = self.public.post(
            "/contact-sales/",
            {
                "contact_name": "Grace Hopper",
                "company_name": "Navy Labs",
                "email": "grace@navy.test",
                "phone": "",
                "plan": str(enterprise.pk),
                "seat_count": "1500",
                "message": "We need a quote.",
            },
        )
        self.assertRedirects(sent, "/contact-sales/sent/", fetch_redirect_response=False)
        row = WorkspaceRequest.objects.get(email="grace@navy.test")
        self.assertEqual(row.kind, WorkspaceRequest.Kind.SALES)
        self.assertEqual(row.requested_slug, "")
        self.assertEqual(row.plan, enterprise)
        self.assertEqual(row.seat_count, 1500)
        self.assertEqual(row.status, WorkspaceRequest.Status.NEW)
        self.assertEqual(Tenant.objects.count(), before)
        self.assertContains(self.public.get("/contact-sales/sent/"), "Sales will be in touch")

    def test_the_sales_form_requires_a_name_company_and_email(self):
        page = self.public.post("/contact-sales/", {"message": "hi"})
        self.assertEqual(page.status_code, 200)
        self.assertFalse(WorkspaceRequest.objects.exists())
        for field in ("contact_name", "company_name", "email"):
            self.assertContains(page, "This field is required", msg_prefix=field)

    def test_the_sales_form_shares_the_request_rate_limit(self):
        data = {"contact_name": "A", "company_name": "B", "email": "a@b.test"}
        for _ in range(5):
            self.assertEqual(self.public.post("/contact-sales/", data).status_code, 302)
        limited = self.public.post("/contact-sales/", data)
        self.assertEqual(limited.status_code, 200)
        self.assertContains(limited, "Too many requests")
        self.assertEqual(WorkspaceRequest.objects.filter(kind="sales").count(), 5)

    def test_request_form_preselects_a_plan_from_the_query(self):
        plan = Plan.objects.get(code="starter")
        page = self.public.get("/request/?plan=starter")
        self.assertContains(page, f'<option value="{plan.pk}" selected>Starter</option>', html=True)
        self.assertNotContains(page, "disabled")
        unknown = self.public.get("/request/?plan=nope")
        self.assertEqual(unknown.status_code, 200)
        self.assertNotContains(unknown, f'<option value="{plan.pk}" selected>Starter</option>', html=True)
        self.assertContains(unknown, '<option value="" selected>No preference</option>', html=True)

    def test_inactive_plan_stays_off_the_pricing_page(self):
        Plan.objects.create(
            code="pilot",
            name="Pilot Hidden",
            monthly_price=500,
            status=Plan.Status.INACTIVE,
            is_active=False,
        )
        page = self.public.get("/pricing/")
        self.assertNotContains(page, "Pilot Hidden")
        self.assertNotContains(self.public.get("/"), "Pilot Hidden")

    def test_csrf_origins_include_the_apex(self):
        origins = platform_csrf_origins("example.com")
        self.assertIn("https://example.com", origins)
        self.assertIn("http://example.com", origins)
        self.assertIn("http://localhost:8000", platform_csrf_origins("localhost"))

    def test_valid_request_is_stored_on_the_control_database(self):
        plan = Plan.objects.get(code="starter")
        created = self.public.post("/request/", _payload(plan=str(plan.pk)))
        self.assertEqual(created.status_code, 302)
        self.assertEqual(created["Location"], "/request/sent/")
        row = WorkspaceRequest.objects.get(requested_slug="northwind")
        self.assertEqual(row._state.db, "default")
        self.assertEqual(row.plan, plan)
        self.assertEqual(row.seat_count, 20)
        self.assertEqual(row.status, WorkspaceRequest.Status.NEW)
        again = self.public.post("/request/", _payload())
        self.assertEqual(again.status_code, 302)
        self.assertEqual(WorkspaceRequest.objects.filter(requested_slug="northwind").count(), 2)
        router = TenantRouter()
        self.assertFalse(router.allow_migrate("tenant_acme", "control", "workspacerequest"))
        self.assertTrue(router.allow_migrate("default", "control", "workspacerequest"))

    def test_reserved_and_taken_slugs_are_rejected(self):
        reserved = self.public.post("/request/", _payload(slug="manage"))
        taken = self.public.post("/request/", _payload(slug="acme"))
        self.assertEqual(reserved.status_code, 200)
        self.assertEqual(taken.status_code, 200)
        self.assertContains(reserved, "reserved")
        self.assertContains(taken, "already in use")
        self.assertEqual(WorkspaceRequest.objects.count(), 0)

    def test_the_sixth_post_in_an_hour_creates_nothing(self):
        for index in range(5):
            response = self.public.post("/request/", _payload(slug=f"team{index}"))
            self.assertEqual(response.status_code, 302)
        blocked = self.public.post("/request/", _payload(slug="team5"))
        self.assertEqual(blocked.status_code, 200)
        self.assertContains(blocked, "Too many requests")
        self.assertFalse(WorkspaceRequest.objects.filter(requested_slug="team5").exists())
        self.assertEqual(WorkspaceRequest.objects.count(), 5)

    def test_workspace_lookup_redirects_only_a_routable_host(self):
        found = self.public.post("/sign-in/", {"slug": "acme"}, HTTP_HOST="localhost:8000")
        self.assertEqual(found.status_code, 302)
        self.assertEqual(found["Location"], "http://acme.localhost:8000/login/")
        unknown = self.public.post("/sign-in/", {"slug": "missing"})
        suspended = self.public.post("/sign-in/", {"slug": "paused"})
        self.assertEqual(unknown.status_code, 200)
        self.assertEqual(suspended.status_code, 200)
        self.assertContains(unknown, "We could not find that workspace.")
        self.assertContains(suspended, "We could not find that workspace.")
        self.assertNotContains(suspended, "not available")

    def test_hosts_stay_apart(self):
        www = Client().get("/pricing/?cycle=annual", HTTP_HOST="www.localhost")
        self.assertEqual(www.status_code, 302)
        self.assertEqual(www["Location"], "http://localhost/pricing/?cycle=annual")

        dashboard = Client().get("/", HTTP_HOST="manage.localhost")
        self.assertEqual(dashboard.status_code, 404)
        self.assertNotContains(dashboard, "Mondays back", status_code=404)

        def get_response(request):
            try:
                resolve(request.path_info, urlconf=request.urlconf)
            except Resolver404:
                return HttpResponseNotFound("missing")
            return HttpResponse("ok")

        tenant = TenantMiddleware(get_response)(
            RequestFactory().get("/request/", HTTP_HOST="acme.localhost")
        )
        self.assertEqual(tenant.status_code, 404)
        self.assertIsNone(get_tenant_alias())

        with CaptureQueriesContext(connection) as captured:
            unknown = Client().get("/pricing/", HTTP_HOST="unknown.localhost")
        self.assertEqual(unknown.status_code, 404)
        sql = " ".join(query["sql"] for query in captured.captured_queries).lower()
        self.assertNotIn("control_workspacerequest", sql)
        self.assertNotIn("employee_employee", sql)
        self.assertIsNone(get_tenant_alias())

    def test_legacy_redirect_still_sends_the_apex_away(self):
        with override_settings(HORILLA_LEGACY_HOST_REDIRECT="cldv.localhost"):
            response = self.public.get("/pricing/")
        self.assertEqual(response.status_code, 302)
        self.assertEqual(response["Location"], "http://cldv.localhost/pricing/")

    def test_ready_stays_off_the_public_host(self):
        with override_settings(
            HORILLA_PLATFORM_DOMAIN="example.com",
            HORILLA_DASHBOARD_HOST="manage.example.com",
            ALLOWED_HOSTS=[".example.com", "manage.example.com", "example.com", "testserver"],
        ):
            client = Client(HTTP_HOST="example.com")
            health = client.get("/health/")
            ready = client.get("/ready/")
        self.assertEqual(health.status_code, 200)
        self.assertContains(health, "clockme")
        self.assertEqual(ready.status_code, 404)

    def _operator_client(self):
        ops = Client(HTTP_HOST="manage.localhost")
        ops.post("/control/login/", {"email": "ops@example.com", "password": "correct-horse"})
        return ops

    def test_provision_form_is_prefilled_from_a_request_and_resolves_it(self):
        plan = Plan.objects.get(code="starter")
        self.public.post("/request/", _payload(plan=str(plan.pk), seat_count="20"))
        row = WorkspaceRequest.objects.get(requested_slug="northwind")
        ops = self._operator_client()

        listing = ops.get("/control/requests/")
        self.assertContains(listing, f"/control/tenants/new/?request={row.pk}")

        form = ops.get(f"/control/tenants/new/?request={row.pk}")
        self.assertEqual(form.status_code, 200)
        initial = form.context["form"].initial
        self.assertEqual(initial["name"], "Northwind")
        self.assertEqual(initial["slug"], "northwind")
        self.assertEqual(initial["admin_name"], "Ada Lovelace")
        self.assertEqual(initial["admin_email"], "ada@northwind.test")
        self.assertEqual(initial["plan"], "starter")
        self.assertEqual(initial["seats"], 20)
        self.assertContains(form, 'value="Northwind"')
        self.assertContains(form, f'name="from_request" value="{row.pk}"')
        self.assertContains(form, "Please set up a workspace.")

        # The operator changes the company name and seat count before queueing.
        queued = ops.post(
            "/control/tenants/new/",
            {
                "from_request": str(row.pk),
                "name": "Northwind Traders",
                "slug": "northwind",
                "admin_name": "Ada Lovelace",
                "admin_email": "ada@northwind.test",
                "plan": "starter",
                "cadence": "monthly",
                "seats": "35",
            },
        )
        self.assertEqual(queued.status_code, 302)
        self.assertEqual(queued["Location"], "/control/tenants/northwind/")
        tenant = Tenant.objects.get(slug="northwind")
        self.assertEqual(tenant.name, "Northwind Traders")
        row.refresh_from_db()
        self.assertEqual(row.status, WorkspaceRequest.Status.REVIEWED)
        self.assertEqual(row.reviewed_by, self.operator)
        audit = OperatorAudit.objects.get(action=OperatorAudit.Action.REQUEST_UPDATE)
        self.assertEqual(audit.detail, f"{row.pk} provisioned")

        again = ops.get("/control/requests/")
        self.assertContains(again, "Open tenant")
        self.assertNotContains(again, f"/control/tenants/new/?request={row.pk}")

    def test_provision_form_flags_a_request_that_does_not_fit(self):
        row = WorkspaceRequest.objects.create(
            company_name="Big Co",
            contact_name="Bo",
            email="bo@big.test",
            requested_slug="acme",
            plan=Plan.objects.get(code="starter"),
            seat_count=100000,
        )
        ops = self._operator_client()
        form = ops.get(f"/control/tenants/new/?request={row.pk}")
        self.assertEqual(form.status_code, 200)
        self.assertContains(form, "allows up to")
        self.assertContains(form, "already exists")
        self.assertLessEqual(form.context["form"].initial["seats"], 100000)

    def test_a_sales_enquiry_is_flagged_for_operators_and_prefills_without_a_slug(self):
        enterprise = Plan.objects.get(code="enterprise")
        self.public.post(
            "/contact-sales/",
            {
                "contact_name": "Grace Hopper",
                "company_name": "Navy Labs",
                "email": "grace@navy.test",
                "plan": str(enterprise.pk),
                "seat_count": "1500",
            },
        )
        row = WorkspaceRequest.objects.get(kind="sales")
        ops = self._operator_client()

        listing = ops.get("/control/requests/")
        self.assertContains(listing, "Talk to Sales")
        self.assertContains(listing, "Navy Labs")
        self.assertContains(listing, f"/control/tenants/new/?request={row.pk}")

        form = ops.get(f"/control/tenants/new/?request={row.pk}")
        self.assertEqual(form.status_code, 200)
        initial = form.context["form"].initial
        self.assertEqual(initial["name"], "Navy Labs")
        self.assertEqual(initial["slug"], "")
        self.assertEqual(initial["plan"], "enterprise")
        self.assertEqual(initial["seats"], 1500)
        self.assertContains(form, "Talk to Sales, so there is no workspace address yet")

    def test_provision_form_ignores_a_bad_request_id(self):
        ops = self._operator_client()
        for value in ("abc", "999999", ""):
            form = ops.get(f"/control/tenants/new/?request={value}")
            self.assertEqual(form.status_code, 200, value)
            self.assertNotContains(form, 'name="from_request"')

    def test_operator_can_review_a_request_and_anonymous_cannot(self):
        self.public.post("/request/", _payload())
        row = WorkspaceRequest.objects.get(requested_slug="northwind")
        anon = Client(HTTP_HOST="manage.localhost")
        denied = anon.post(f"/control/requests/{row.pk}/reviewed/")
        self.assertEqual(denied.status_code, 302)
        self.assertIn("/control/login/", denied["Location"])
        row.refresh_from_db()
        self.assertEqual(row.status, WorkspaceRequest.Status.NEW)

        ops = Client(HTTP_HOST="manage.localhost")
        ops.post(
            "/control/login/",
            {"email": "ops@example.com", "password": "correct-horse"},
        )
        listing = ops.get("/control/requests/")
        self.assertEqual(listing.status_code, 200)
        self.assertContains(listing, "Northwind")
        self.assertContains(listing, "/control/tenants/new/")
        self.assertEqual(listing.context["nav_request_count"], 1)

        reviewed = ops.post(f"/control/requests/{row.pk}/reviewed/")
        self.assertEqual(reviewed.status_code, 302)
        row.refresh_from_db()
        self.assertEqual(row.status, WorkspaceRequest.Status.REVIEWED)
        self.assertEqual(row.reviewed_by, self.operator)
        audit = OperatorAudit.objects.get(action=OperatorAudit.Action.REQUEST_UPDATE)
        self.assertEqual(audit.category, OperatorAudit.Category.PROVISIONING)
        self.assertEqual(audit.detail, f"{row.pk} reviewed")
        self.assertNotIn("ada@northwind.test", audit.detail)

        dismissed = ops.post(f"/control/requests/{row.pk}/dismissed/")
        self.assertEqual(dismissed.status_code, 302)
        row.refresh_from_db()
        self.assertEqual(row.status, WorkspaceRequest.Status.DISMISSED)
