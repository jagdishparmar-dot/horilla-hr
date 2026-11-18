import os
from unittest import mock

from cryptography.fernet import Fernet
from django.contrib.auth.hashers import identify_hasher
from django.core.exceptions import ImproperlyConfigured
from django.core.management import call_command
from django.core.management.base import CommandError
from django.db import connections
from django.test import SimpleTestCase, TestCase, override_settings

from control.context import (
    activate_tenant_alias,
    clear_tenant_alias,
    get_tenant_alias,
)
from control.crypto import (
    decrypt_tenant_password,
    encrypt_tenant_password,
    redact_job_error,
)
from control.db import ensure_tenant_connection
from control.models import Domain, Operator, ProvisionJob, Tenant
from control.naming import TenantSlugError
from control.router import CONTROL_APP_LABELS, TenantRouter, TenantRoutingError
from employee.models import Employee


def _use_fernet_key():
    key = Fernet.generate_key().decode()
    return mock.patch.dict(os.environ, {"TENANT_DB_FERNET_KEY": key})


class CryptoTests(SimpleTestCase):
    def test_round_trip(self):
        with _use_fernet_key():
            token = encrypt_tenant_password("s3cret-db")
            self.assertNotIn("s3cret-db", token)
            self.assertEqual(decrypt_tenant_password(token), "s3cret-db")

    def test_missing_key_raises_at_first_use(self):
        with mock.patch.dict(os.environ, {"TENANT_DB_FERNET_KEY": ""}, clear=False):
            os.environ.pop("TENANT_DB_FERNET_KEY", None)
            with self.assertRaises(ImproperlyConfigured) as caught:
                encrypt_tenant_password("s3cret-db")
        self.assertNotIn("s3cret-db", str(caught.exception))

    def test_job_error_redacts_assignments(self):
        text = redact_job_error("login failed password=s3cret-db token: abc")
        self.assertNotIn("s3cret-db", text)
        self.assertIn("[redacted]", text)


class RouterTests(SimpleTestCase):
    def test_control_apps_are_not_hr_apps(self):
        self.assertIn("control", CONTROL_APP_LABELS)
        self.assertNotIn("employee", CONTROL_APP_LABELS)
        self.assertNotIn("horilla_auth", CONTROL_APP_LABELS)

    @override_settings(HORILLA_MULTITENANT=True)
    def test_employee_query_without_alias_fails(self):
        clear_tenant_alias()
        with self.assertRaises(TenantRoutingError):
            list(Employee.objects.all())

    @override_settings(HORILLA_MULTITENANT=True)
    def test_migrate_control_does_not_allow_employee_on_default(self):
        router = TenantRouter()
        self.assertTrue(router.allow_migrate("default", "control"))
        self.assertFalse(router.allow_migrate("default", "employee"))
        self.assertTrue(router.allow_migrate("tenant_acme", "employee"))
        self.assertFalse(router.allow_migrate("tenant_acme", "control"))
        self.assertTrue(router.allow_migrate("default", "auth"))
        self.assertTrue(router.allow_migrate("tenant_acme", "auth"))
        self.assertTrue(router.allow_migrate("tenant_acme", "contenttypes"))
        self.assertTrue(router.allow_migrate("default", "sessions"))
        self.assertFalse(router.allow_migrate("tenant_acme", "sessions"))

    @override_settings(HORILLA_MULTITENANT=True)
    def test_auth_follows_the_tenant_and_sessions_stay_on_control(self):
        from django.contrib.auth.models import Group
        from django.contrib.contenttypes.models import ContentType
        from django.contrib.sessions.models import Session

        router = TenantRouter()
        clear_tenant_alias()
        self.assertEqual(router.db_for_read(Group), "default")
        self.assertEqual(router.db_for_read(ContentType), "default")
        self.assertEqual(router.db_for_read(Session), "default")
        token = activate_tenant_alias("tenant_acme")
        try:
            self.assertEqual(router.db_for_read(Group), "tenant_acme")
            self.assertEqual(router.db_for_write(ContentType), "tenant_acme")
            self.assertEqual(router.db_for_read(Session), "default")
        finally:
            clear_tenant_alias(token)

    @override_settings(HORILLA_MULTITENANT=False)
    def test_single_tenant_mode_keeps_the_current_database(self):
        router = TenantRouter()
        self.assertIsNone(router.allow_migrate("default", "employee"))
        self.assertIsNone(router.db_for_read(Employee))


class ModelTests(TestCase):
    def test_operator_is_not_the_auth_user_model(self):
        from django.conf import settings

        self.assertEqual(settings.AUTH_USER_MODEL, "horilla_auth.HorillaUser")
        operator = Operator(email="ops@example.com")
        operator.set_password("correct-horse")
        operator.save()
        self.assertNotEqual(operator.password, "correct-horse")
        identify_hasher(operator.password)
        self.assertTrue(operator.check_password("correct-horse"))
        self.assertNotIn("correct-horse", str(operator))

    def test_tenant_string_hides_ciphertext_and_slug_cannot_change(self):
        with _use_fernet_key():
            tenant = Tenant(name="Acme", slug="acme")
            tenant.set_db_password("s3cret-db")
            tenant.save()
            self.assertEqual(tenant.db_name, "tenant_acme")
            self.assertEqual(tenant.db_user, "tenant_acme")
            self.assertEqual(tenant.db_password(), "s3cret-db")
            rendered = str(tenant)
            self.assertNotIn("s3cret-db", rendered)
            self.assertNotIn(tenant.db_password_encrypted, rendered)
            tenant.slug = "beta"
            with self.assertRaises(TenantSlugError):
                tenant.save()

    def test_domain_and_job_rows(self):
        tenant = Tenant.objects.create(name="Acme", slug="acme")
        Domain.objects.create(tenant=tenant, host="acme.localhost", is_primary=True, verified=True)
        job = ProvisionJob.objects.create(tenant=tenant, kind=ProvisionJob.Kind.CREATE)
        job.set_error("password=s3cret-db")
        job.save()
        job.refresh_from_db()
        self.assertNotIn("s3cret-db", job.error)


class ConnectionTests(TestCase):
    def test_registers_alias_without_logging_password(self):
        with _use_fernet_key():
            tenant = Tenant(name="Acme", slug="acme", db_host="db", db_port=5432)
            tenant.set_db_password("s3cret-db")
            tenant.save()
            alias = ensure_tenant_connection(tenant)
            try:
                config = connections.databases[alias]
                self.assertEqual(config["NAME"], "tenant_acme")
                self.assertEqual(config["USER"], "tenant_acme")
                self.assertEqual(config["PASSWORD"], "s3cret-db")
                self.assertEqual(config["CONN_MAX_AGE"], 0)
                self.assertEqual(config["OPTIONS"]["connect_timeout"], 5)
                self.assertTrue(config["CONN_HEALTH_CHECKS"])
            finally:
                connections.databases.pop(alias, None)


class MigrateTenantsTests(TestCase):
    def _tenant(self, slug, status):
        return Tenant.objects.create(name=slug, slug=slug, status=status)

    def test_skips_suspended_and_continues_after_a_failure(self):
        active_ok = self._tenant("acme", Tenant.Status.ACTIVE)
        active_bad = self._tenant("beta", Tenant.Status.ACTIVE)
        suspended = self._tenant("gama", Tenant.Status.SUSPENDED)

        def migrate_side_effect(*args, **kwargs):
            if kwargs.get("database") == "tenant_beta":
                raise RuntimeError("password=s3cret-db boom")

        with mock.patch(
            "control.management.commands.migrate_tenants.ensure_tenant_connection",
            side_effect=lambda tenant: f"tenant_{tenant.slug}",
        ) as ensure, mock.patch(
            "control.management.commands.migrate_tenants.call_command",
            side_effect=migrate_side_effect,
        ):
            with self.assertRaises(CommandError):
                call_command("migrate_tenants")

        ensured = {call.args[0].slug for call in ensure.call_args_list}
        self.assertEqual(ensured, {"acme", "beta"})
        self.assertNotIn(suspended.slug, ensured)
        bad = ProvisionJob.objects.get(tenant=active_bad, kind=ProvisionJob.Kind.MIGRATE)
        good = ProvisionJob.objects.get(tenant=active_ok, kind=ProvisionJob.Kind.MIGRATE)
        self.assertEqual(bad.status, ProvisionJob.Status.FAILED)
        self.assertEqual(bad.error, "RuntimeError")
        self.assertEqual(good.status, ProvisionJob.Status.SUCCEEDED)
        self.assertIsNone(get_tenant_alias())

    def test_include_suspended(self):
        self._tenant("gama", Tenant.Status.SUSPENDED)
        with mock.patch(
            "control.management.commands.migrate_tenants.ensure_tenant_connection",
            return_value="tenant_gama",
        ), mock.patch(
            "control.management.commands.migrate_tenants.call_command",
        ) as migrate:
            call_command("migrate_tenants", include_suspended=True)
        migrate.assert_called_once()
        self.assertEqual(
            migrate.call_args.kwargs["database"],
            "tenant_gama",
        )


class AliasContextTests(SimpleTestCase):
    def test_activate_and_clear(self):
        clear_tenant_alias()
        token = activate_tenant_alias("tenant_acme")
        self.assertEqual(get_tenant_alias(), "tenant_acme")
        clear_tenant_alias(token)
        self.assertIsNone(get_tenant_alias())
