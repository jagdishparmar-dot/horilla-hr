"""Acceptance tests for database-per-tenant isolation.

Two real PostgreSQL databases are created and migrated once for this class.
That migrate is the slow part. The tests then prove a login, a primary key,
a session cookie, the cache, a media path, the scheduler, and a database role
cannot cross from one tenant to the other.
"""

import os

from cryptography.fernet import Fernet
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.db import connections
from django.db.backends.postgresql.base import Database as PgDatabase
from django.test import Client, TestCase, override_settings

from base.models import Company
from control.context import activate_tenant_alias, clear_tenant_alias, get_tenant_alias
from control.db import ensure_tenant_connection
from control.models import Domain, ProvisionJob, Tenant
from control.provisioning import (
    _step_create_database,
    _step_create_role,
    _step_grant_connect,
    _step_revoke_other_roles,
    _step_revoke_public,
    _step_store_connection,
    maintenance_cursor,
    migrate_tenant,
    quote_ident,
)
from control.router import TenantRoutingError
from employee.models import Employee
from horilla.scheduling import _REGISTRY, register_job, run_registered_job

SLUGS = ("p7isoa", "p7isob")
EMAIL = "ada@example.com"
PASSWORD = "shared-secret-1"
BADGE = "E100"


class TenantIsolationTests(TestCase):
    databases = {"default"}
    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        # Added after discovery so system checks do not open aliases that
        # do not exist yet. The test guard allows a connection only when
        # its alias is in this set.
        cls.databases = set(cls.databases) | {"tenant_p7isoa", "tenant_p7isob"}
        # Migrate has to see the flag or it writes the HR schema into the
        # control test database.
        cls._override = override_settings(
            HORILLA_MULTITENANT=True,
            HORILLA_PLATFORM_DOMAIN="localhost",
            HORILLA_DASHBOARD_HOST="manage.localhost",
            ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
        )
        cls._override.enable()
        os.environ["TENANT_DB_FERNET_KEY"] = Fernet.generate_key().decode()
        cls._drop_databases()
        Tenant.objects.filter(slug__in=SLUGS).delete()
        cls.tenants = {}
        try:
            cls._provision()
        except Exception:
            Tenant.objects.filter(slug__in=SLUGS).delete()
            cls._drop_databases()
            raise

    @classmethod
    def _provision(cls):
        for slug in SLUGS:
            tenant = Tenant.objects.create(
                name=slug,
                slug=slug,
                status=Tenant.Status.PROVISIONING,
            )
            job = ProvisionJob(tenant=tenant)
            _step_create_role(job)
            _step_create_database(job)
            _step_revoke_public(job)
            _step_grant_connect(job)
            _step_revoke_other_roles(job)
            _step_store_connection(job)
            migrate_tenant(tenant)
            tenant.status = Tenant.Status.ACTIVE
            tenant.save(update_fields=["status"])
            Domain.objects.create(
                tenant=tenant,
                host=f"{slug}.localhost",
                is_primary=True,
                verified=True,
            )
            cls.tenants[slug] = tenant
        cls.employee_ids = {}
        cls.employee_ids["p7isoa"] = cls._seed(cls.tenants["p7isoa"], "P7Ada")
        cls.only_b_id = cls._seed(cls.tenants["p7isob"], "P7Bea", extra=True)
        # Leave tenant aliases out of the per-test transaction. Middleware
        # closes those connections, and an open atomic block cannot survive that.
        cls.databases = {"default"}

    def setUp(self):
        super().setUp()
        self.__class__.databases = {"default", "tenant_p7isoa", "tenant_p7isob"}

    def tearDown(self):
        self.__class__.databases = {"default"}
        super().tearDown()

    @classmethod
    def tearDownClass(cls):
        try:
            Tenant.objects.filter(slug__in=SLUGS).delete()
            cls._drop_databases()
        finally:
            os.environ.pop("TENANT_DB_FERNET_KEY", None)
            # _drop_databases already removed the tenant aliases. Leave
            # databases as default so teardown does not reopen them. Class
            # cleanup unwraps aliases that are still registered and not listed
            # here, and those raw methods have no .wrapped.
            override = getattr(cls, "_override", None)
            if override is not None and hasattr(override, "wrapped"):
                override.disable()
            super().tearDownClass()

    @classmethod
    def _drop_databases(cls):
        for alias in list(connections):
            if not alias.startswith("tenant_p7iso"):
                continue
            connections[alias].close()
            connections.settings.pop(alias, None)
            if hasattr(connections._connections, alias):
                delattr(connections._connections, alias)
        with maintenance_cursor() as cursor:
            for slug in SLUGS:
                name = quote_ident(f"tenant_{slug}")
                cursor.execute(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
                cursor.execute(f"DROP ROLE IF EXISTS {name}")

    @classmethod
    def _seed(cls, tenant, first_name, extra=False):
        alias = ensure_tenant_connection(tenant)
        token = activate_tenant_alias(alias)
        try:
            User = get_user_model()
            user = User.objects.create_user(
                username=EMAIL,
                email=EMAIL,
                password=PASSWORD,
            )
            user.first_name = first_name
            user.is_staff = True
            user.is_superuser = True
            user.is_new_employee = False
            user.save()
            employee = Employee(
                employee_user_id=user,
                employee_first_name=first_name,
                employee_last_name="Tester",
                email=EMAIL,
                phone="0000000000",
                badge_id=BADGE,
            )
            employee.save()
            if not extra:
                return employee.pk
            other = User.objects.create_user(
                username="onlyb@example.com",
                email="onlyb@example.com",
                password=PASSWORD,
            )
            only_b = Employee(
                employee_user_id=other,
                employee_first_name="OnlyB",
                employee_last_name="Tester",
                email="onlyb@example.com",
                phone="0000000001",
                badge_id="E200",
            )
            only_b.save()
            cls.employee_ids["p7isob"] = employee.pk
            return only_b.pk
        finally:
            clear_tenant_alias(token)

    def _client(self, slug):
        return Client(HTTP_HOST=f"{slug}.localhost")

    def _login(self, client):
        response = client.post(
            "/login/",
            {"username": EMAIL, "password": PASSWORD},
        )
        self.assertEqual(response.status_code, 302, response.content[:500])
        return response

    def test_same_email_and_badge_login_returns_only_that_tenant(self):
        for slug, first_name in (("p7isoa", "P7Ada"), ("p7isob", "P7Bea")):
            client = self._client(slug)
            self._login(client)
            self.assertEqual(client.session.get("tenant_slug"), slug)
            response = client.get(
                f"/employee/employee-view/{self.employee_ids[slug]}/"
            )
            self.assertEqual(response.status_code, 200)
            self.assertContains(response, first_name)
            other = "P7Bea" if first_name == "P7Ada" else "P7Ada"
            self.assertNotContains(response, other)

    def test_other_tenants_employee_id_is_404(self):
        client = self._client("p7isoa")
        self._login(client)
        response = client.get(f"/employee/employee-view/{self.only_b_id}/")
        self.assertEqual(response.status_code, 404)
        self.assertNotContains(response, "OnlyB", status_code=404)

    def test_session_cookie_is_not_portable(self):
        first = self._client("p7isoa")
        self._login(first)
        cookie = first.cookies["sessionid"]
        self.assertFalse(cookie["domain"])

        second = self._client("p7isob")
        self.assertNotIn("sessionid", second.cookies)

        second.cookies["sessionid"] = cookie.value
        response = second.get(
            f"/employee/employee-view/{self.employee_ids['p7isoa']}/"
        )
        self.assertEqual(response.status_code, 302)
        self.assertIn("/login/", response.url)
        self.assertNotIn("_auth_user_id", second.session)

    def test_cache_and_media_cannot_cross(self):
        key = "phase7-marker"
        for slug, value in (("p7isoa", "from-a"), ("p7isob", "from-b")):
            token = activate_tenant_alias(f"tenant_{slug}")
            try:
                cache.set(key, value)
            finally:
                clear_tenant_alias(token)
        for slug, value in (("p7isoa", "from-a"), ("p7isob", "from-b")):
            token = activate_tenant_alias(f"tenant_{slug}")
            try:
                self.assertEqual(cache.get(key), value)
                cache.delete(key)
            finally:
                clear_tenant_alias(token)

        client = self._client("p7isoa")
        response = client.get("/media/p7isob/employee/secret.txt")
        self.assertEqual(response.status_code, 404)

    def test_scheduler_without_an_alias_aborts_and_writes_only_its_alias(self):
        def write_marker():
            if not get_tenant_alias():
                raise TenantRoutingError("Scheduled job has no tenant database.")
            Company.objects.create(
                company=f"marker-{get_tenant_alias()}",
                address="",
            )

        with self.assertRaises(TenantRoutingError):
            write_marker()

        register_job(write_marker, "interval", job_id="phase7.marker", minutes=5)
        try:
            run_registered_job("phase7.marker")
        finally:
            _REGISTRY.pop("phase7.marker", None)

        for slug in SLUGS:
            token = activate_tenant_alias(f"tenant_{slug}")
            try:
                own = f"marker-tenant_{slug}"
                other = f"marker-tenant_{'p7isob' if slug == 'p7isoa' else 'p7isoa'}"
                self.assertTrue(Company.objects.filter(company=own).exists())
                self.assertFalse(Company.objects.filter(company=other).exists())
            finally:
                clear_tenant_alias(token)

    def test_direct_database_login_cannot_cross(self):
        from django.conf import settings

        intruder = self.tenants["p7isob"]
        intruder.refresh_from_db()
        default = settings.DATABASES["default"]
        with self.assertRaises(PgDatabase.OperationalError) as caught:
            PgDatabase.connect(
                host=default.get("HOST") or "db",
                port=int(default.get("PORT") or 5432),
                dbname="tenant_p7isoa",
                user="tenant_p7isob",
                password=intruder.db_password(),
                connect_timeout=5,
            )
        message = str(caught.exception).lower()
        self.assertIn("permission denied", message)
        self.assertNotIn(intruder.db_password(), str(caught.exception))
