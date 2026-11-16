import os
from unittest import mock

from cryptography.fernet import Fernet
from django.conf import settings
from django.contrib.sessions.middleware import SessionMiddleware
from django.db import connection, connections
from django.http import HttpResponse, HttpResponseNotFound
from django.test import Client, RequestFactory, TestCase, override_settings
from django.test.utils import CaptureQueriesContext
from django.utils import timezone

from base.middleware import CompanyMiddleware
from control.context import clear_tenant_alias, get_tenant_alias
from control.middleware import TenantMiddleware
from control.models import Domain, Operator, ProvisionJob, Tenant
from control.readiness import tenant_migration_status

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _response_ok(request):
    return HttpResponse("ok")


@MULTI
class TenantRoutingTests(TestCase):
    def setUp(self):
        super().setUp()
        key = Fernet.generate_key().decode()
        self._env = mock.patch.dict(os.environ, {"TENANT_DB_FERNET_KEY": key})
        self._env.start()
        self.factory = RequestFactory()
        self.operator = Operator(email="hidden-operator@example.com")
        self.operator.set_password("correct-horse")
        self.operator.save()
        self.acme = self._tenant("acme")
        self.beta = self._tenant("beta")
        self.suspended = self._tenant("gama", status=Tenant.Status.SUSPENDED)

    def tearDown(self):
        clear_tenant_alias()
        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        self._env.stop()
        super().tearDown()

    def _tenant(self, slug, status=Tenant.Status.ACTIVE):
        tenant = Tenant(
            name=slug,
            slug=slug,
            status=status,
            db_host="db",
            db_port=5432,
        )
        tenant.set_db_password("s3cret-db")
        tenant.save()
        Domain.objects.create(
            tenant=tenant,
            host=f"{slug}.localhost",
            is_primary=True,
            verified=True,
        )
        return tenant

    def test_two_requests_do_not_leak_the_alias(self):
        seen = []

        def get_response(request):
            seen.append(get_tenant_alias())
            return HttpResponse("ok")

        middleware = TenantMiddleware(get_response)
        self.assertNotIn("tenant_acme", connections.databases)
        middleware(self.factory.get("/", HTTP_HOST="acme.localhost"))
        self.assertEqual(seen, ["tenant_acme"])
        self.assertNotIn("tenant_acme", settings.DATABASES)
        self.assertEqual(connections.databases["tenant_acme"]["PASSWORD"], "s3cret-db")
        self.assertEqual(connections.databases["tenant_acme"]["CONN_MAX_AGE"], 0)
        self.assertNotIn("tenant_beta", connections.databases)
        self.assertIsNone(get_tenant_alias())

        middleware(self.factory.get("/", HTTP_HOST="beta.localhost"))
        self.assertEqual(seen, ["tenant_acme", "tenant_beta"])
        self.assertIsNone(get_tenant_alias())

    def test_unknown_host_reads_neither_operators_nor_employees(self):
        client = Client()
        with CaptureQueriesContext(connection) as captured:
            response = client.get("/employee/", HTTP_HOST="unknown.localhost")
        self.assertEqual(response.status_code, 404)
        self.assertNotIn(b"hidden-operator@example.com", response.content)
        sql = " ".join(query["sql"] for query in captured.captured_queries).lower()
        self.assertNotIn("employee_employee", sql)
        self.assertNotIn("control_operator", sql)
        self.assertIsNone(get_tenant_alias())

    def test_suspended_host_is_forbidden_without_a_tenant_alias(self):
        response = Client().get("/health/", HTTP_HOST="gama.localhost")
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("tenant_gama", connections.databases)

    def test_dashboard_and_tenant_urlconfs_stay_apart(self):
        from django.urls import Resolver404, resolve

        def get_response(request):
            try:
                resolve(request.path_info, urlconf=request.urlconf)
            except Resolver404:
                return HttpResponseNotFound("missing")
            return HttpResponse("ok")

        middleware = TenantMiddleware(get_response)
        dashboard_employee = middleware(
            self.factory.get("/employee/", HTTP_HOST="manage.localhost")
        )
        dashboard_home = middleware(
            self.factory.get("/control/", HTTP_HOST="manage.localhost")
        )
        tenant_control = middleware(
            self.factory.get("/control/", HTTP_HOST="acme.localhost")
        )
        tenant_health = middleware(
            self.factory.get("/health/", HTTP_HOST="acme.localhost")
        )
        self.assertEqual(dashboard_employee.status_code, 404)
        self.assertEqual(dashboard_home.status_code, 200)
        self.assertEqual(tenant_control.status_code, 404)
        self.assertEqual(tenant_health.status_code, 200)
        self.assertIsNone(get_tenant_alias())

        client = Client()
        with override_settings(DEBUG=False):
            self.assertEqual(
                client.get("/health/", HTTP_HOST="manage.localhost").status_code,
                200,
            )
            employee = client.get("/employee/", HTTP_HOST="manage.localhost")
        self.assertEqual(employee.status_code, 404)
        self.assertNotIn(b"hidden-operator@example.com", employee.content)

    def test_ready_reports_a_failed_tenant_migration_without_tenant_data(self):
        ProvisionJob.objects.create(
            tenant=self.acme,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.FAILED,
            step="migrate",
            error="password=s3cret-db",
            finished_at=timezone.now(),
        )
        self.assertEqual(tenant_migration_status(), "failed:acme")
        response = Client().get("/ready/", HTTP_HOST="manage.localhost")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["tenant_migrations"], "failed:acme")
        self.assertNotIn("s3cret-db", response.content.decode())

    def test_company_middleware_skips_lookup_without_a_tenant_alias(self):
        called = []

        def get_response(request):
            called.append(True)
            return HttpResponse("ok")

        request = self.factory.get("/")
        request.user = mock.Mock(is_authenticated=True)
        clear_tenant_alias()
        CompanyMiddleware(get_response)(request)
        self.assertEqual(called, [True])


class SessionCookieTests(TestCase):
    def test_session_cookie_is_host_only(self):
        request = RequestFactory().get("/health/", HTTP_HOST="acme.localhost")

        def view(req):
            req.session["marker"] = "a"
            return HttpResponse("ok")

        response = SessionMiddleware(view)(request)
        self.assertEqual(response.cookies["sessionid"]["domain"], "")
