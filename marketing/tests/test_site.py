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
        for path in ("/", "/features/", "/pricing/", "/sign-in/", "/request/", "/request/sent/"):
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

    def test_pricing_shows_each_cycle_as_a_per_month_price(self):
        page = self.public.get("/pricing/")
        for cycle in ("monthly", "semiannual", "annual"):
            self.assertContains(page, f'id="cycle-{cycle}"')
            self.assertContains(page, f'data-cycle="{cycle}"')
        # Starter: 7,680 a year is 640 a month, 4,800 per half year is 800.
        self.assertContains(page, "₹640")
        self.assertContains(page, "?plan=starter")
        self.assertNotContains(page, "Unassigned")

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
