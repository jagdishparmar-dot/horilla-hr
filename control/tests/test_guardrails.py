import os
from unittest import mock

from django.core.exceptions import ImproperlyConfigured
from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import SimpleTestCase

from control.naming import (
    TenantSlugError,
    assert_slug_unchanged,
    tenant_database_name,
    tenant_role_name,
    validate_tenant_slug,
)
from control.secrets import tenant_db_fernet_key


class TenantSlugTests(SimpleTestCase):
    def test_accepts_a_normal_slug(self):
        self.assertEqual(validate_tenant_slug("Acme"), "acme")
        self.assertEqual(tenant_database_name("acme"), "tenant_acme")
        self.assertEqual(tenant_role_name("acme"), "tenant_acme")

    def test_rejects_shape_and_reserved_names(self):
        for slug in ("", "ab", "Acme-Co", "1acme", "has space", "postgres", "public", "manage", "www"):
            with self.assertRaises(TenantSlugError):
                validate_tenant_slug(slug)

    def test_slug_is_immutable(self):
        self.assertEqual(assert_slug_unchanged("acme", "acme"), "acme")
        with self.assertRaises(TenantSlugError):
            assert_slug_unchanged("acme", "beta")

    def test_provision_command_rejects_a_bad_slug(self):
        with self.assertRaises(CommandError):
            call_command("provision_tenant", "Postgres")

    def test_provision_command_accepts_without_creating_anything(self):
        call_command("provision_tenant", "acme")


class TenantSecretTests(SimpleTestCase):
    def test_missing_key_is_allowed_while_multitenant_is_off(self):
        with mock.patch.dict(os.environ, {"HORILLA_MULTITENANT": "0"}, clear=False):
            os.environ.pop("TENANT_DB_FERNET_KEY", None)
            self.assertEqual(tenant_db_fernet_key(), "")

    def test_missing_key_fails_when_multitenant_is_on(self):
        env = {"HORILLA_MULTITENANT": "true"}
        with mock.patch.dict(os.environ, env, clear=False):
            os.environ.pop("TENANT_DB_FERNET_KEY", None)
            with self.assertRaises(ImproperlyConfigured):
                tenant_db_fernet_key()

    def test_key_value_is_not_required_in_the_error_text(self):
        env = {"HORILLA_MULTITENANT": "1", "TENANT_DB_FERNET_KEY": ""}
        with mock.patch.dict(os.environ, env, clear=False):
            with self.assertRaises(ImproperlyConfigured) as caught:
                tenant_db_fernet_key()
        self.assertNotIn("password", str(caught.exception).lower())


class CookieDomainTests(SimpleTestCase):
    def test_cookies_are_host_only(self):
        from django.conf import settings

        self.assertIsNone(settings.SESSION_COOKIE_DOMAIN)
        self.assertIsNone(settings.CSRF_COOKIE_DOMAIN)
