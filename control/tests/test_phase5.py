import os
import stat
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

from cryptography.fernet import Fernet
from django.contrib.auth import get_user_model
from django.core.cache import cache
from django.core.management import call_command
from django.core.management.base import CommandError
from django.http import Http404
from django.test import RequestFactory, TestCase, override_settings
from rest_framework_simplejwt.exceptions import AuthenticationFailed
from rest_framework_simplejwt.tokens import RefreshToken

from base.views import protected_media
from control.backup import dump_tenant_database, resolve_dump
from control.context import activate_tenant_alias, clear_tenant_alias, get_tenant_alias
from control.models import Tenant
from control.provisioning import ProvisionError, _run_restore
from horilla.cache import CacheNamespaceError
from horilla.isolation import activate_cache_scope, clear_cache_scope
from horilla.models import upload_path
from horilla.scheduling import register_job, run_registered_job
from horilla_api.authentication import TenantScopedJWTAuthentication
from pg_backup.scheduler import backup_postgres

LOCALE_CACHE = override_settings(
    HORILLA_MULTITENANT=True,
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "phase5",
            "KEY_FUNCTION": "horilla.cache.tenant_cache_key",
        }
    },
)


class Bare:
    def __init__(self):
        self._meta = SimpleNamespace(app_label="employee", model_name="employee")


@LOCALE_CACHE
class RuntimeIsolationTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_cache_keys_are_per_tenant_and_control(self):
        with self.assertRaises(CacheNamespaceError):
            cache.set("employees", 1)
        acme = activate_tenant_alias("tenant_acme")
        try:
            cache.set("employees", 1)
            self.assertEqual(cache.get("employees"), 1)
        finally:
            clear_tenant_alias(acme)
        beta = activate_tenant_alias("tenant_beta")
        try:
            self.assertIsNone(cache.get("employees"))
        finally:
            clear_tenant_alias(beta)
        scope = activate_cache_scope("control")
        try:
            cache.set("employees", 9)
            self.assertEqual(cache.get("employees"), 9)
        finally:
            clear_cache_scope(scope)
        again = activate_tenant_alias("tenant_acme")
        try:
            self.assertEqual(cache.get("employees"), 1)
        finally:
            clear_tenant_alias(again)

    def test_uploads_and_downloads_stay_under_the_slug(self):
        with self.assertRaises(ValueError):
            upload_path(Bare(), "note.txt")
        token = activate_tenant_alias("tenant_acme")
        try:
            stored = upload_path(Bare(), "note.txt")
        finally:
            clear_tenant_alias(token)
        self.assertTrue(stored.startswith("acme/employee/employee/"))
        request = RequestFactory().get("/media/beta/employee/note.txt")
        request.tenant = SimpleNamespace(slug="acme")
        with self.assertRaises(Http404):
            protected_media(request, "beta/employee/note.txt")

    def test_scheduler_logs_and_continues(self):
        Tenant.objects.create(name="One", slug="one", status=Tenant.Status.ACTIVE)
        Tenant.objects.create(name="Two", slug="two", status=Tenant.Status.ACTIVE)
        seen = []

        def explode():
            seen.append(get_tenant_alias())
            if len(seen) == 1:
                raise RuntimeError("first tenant")

        register_job(explode, "interval", job_id="phase5.explode", minutes=5)
        with mock.patch(
            "control.db.ensure_tenant_connection",
            side_effect=lambda tenant: f"tenant_{tenant.slug}",
        ):
            run_registered_job("phase5.explode")
        self.assertEqual(seen, ["tenant_one", "tenant_two"])

    def test_hr_command_requires_a_slug(self):
        with self.assertRaises(CommandError):
            call_command("create_default_themes")
        tenant = Tenant.objects.create(name="Acme", slug="acme", status=Tenant.Status.ACTIVE)
        seen = []

        def record(self, *args, **kwargs):
            seen.append(get_tenant_alias())

        with mock.patch(
            "horilla.tenant_command.ensure_tenant_connection",
            return_value="tenant_acme",
        ), mock.patch(
            "horilla_theme.management.commands.create_default_themes.Command.handle",
            record,
        ):
            call_command("create_default_themes", slug="acme")
        self.assertEqual(seen, ["tenant_acme"])
        self.assertEqual(tenant.slug, "acme")

    def test_backup_uses_the_tenant_database_and_restore_stays_in_its_folder(self):
        tenant = Tenant.objects.create(
            name="Acme",
            slug="acme",
            status=Tenant.Status.ACTIVE,
            db_name="tenant_acme",
            db_user="tenant_acme",
            db_host="db",
            db_port=5432,
        )
        tenant.set_db_password("db-secret")
        tenant.save()

        captured = {}

        def fake_run(command, **kwargs):
            captured["command"] = command
            captured["env"] = kwargs.get("env") or {}
            path = command[command.index("-f") + 1]
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(b"dump")
            return mock.Mock(returncode=0)

        modes = []
        real_chmod = Path.chmod

        def spy_chmod(self, mode):
            modes.append(mode)
            return real_chmod(self, mode)

        with mock.patch("shutil.which", return_value="/usr/bin/pg_dump"), mock.patch(
            "control.backup.subprocess.run", side_effect=fake_run
        ), mock.patch.object(Path, "chmod", spy_chmod):
            path = dump_tenant_database(tenant)
        command = captured["command"]
        self.assertIn("tenant_acme", command)
        self.assertNotIn("db-secret", command)
        self.assertEqual(captured["env"].get("PGPASSWORD"), "db-secret")
        self.assertNotIn(self._default_name(), command)
        self.assertIn("backups/acme/", path.replace("\\", "/"))
        self.assertIn(stat.S_IRUSR | stat.S_IWUSR | stat.S_IRGRP, modes)
        os.remove(path)

        with self.assertRaises(ProvisionError):
            resolve_dump("acme", "beta/ok.dump")

        job_tenant = tenant
        from control.models import ProvisionJob

        job = ProvisionJob.objects.create(
            tenant=job_tenant,
            kind=ProvisionJob.Kind.RESTORE,
            status=ProvisionJob.Status.RUNNING,
            payload={"dump_name": "missing.dump"},
        )
        with mock.patch(
            "control.backup.restore_tenant_database",
            side_effect=ProvisionError("Tenant restore failed."),
        ):
            with self.assertRaises(ProvisionError):
                _run_restore(job)
        job.tenant.refresh_from_db()
        self.assertEqual(job.tenant.status, Tenant.Status.SUSPENDED)

        with mock.patch("control.backup.restore_tenant_database", return_value=None):
            _run_restore(job)
        job.tenant.refresh_from_db()
        self.assertEqual(job.tenant.status, Tenant.Status.ACTIVE)

        other = Tenant.objects.create(name="Beta", slug="beta", status=Tenant.Status.ACTIVE)
        with mock.patch("control.provisioning.enqueue_backup") as enqueue:
            backup_postgres()
        self.assertGreaterEqual(enqueue.call_count, 2)
        slugs = {call.args[0].slug for call in enqueue.call_args_list}
        self.assertIn(tenant.slug, slugs)
        self.assertIn(other.slug, slugs)

    def test_token_for_one_tenant_is_rejected_on_another(self):
        with override_settings(HORILLA_MULTITENANT=False):
            user = get_user_model().objects.create_user(
                username="ada@acme.test",
                email="ada@acme.test",
                password="temporary-secret",
            )
            refresh = RefreshToken.for_user(user)
            refresh["tenant_slug"] = "acme"
            access = str(refresh.access_token)
        request = RequestFactory().get(
            "/api/employees/",
            HTTP_AUTHORIZATION=f"Bearer {access}",
        )
        request.tenant = SimpleNamespace(slug="beta")
        auth = TenantScopedJWTAuthentication()
        with mock.patch.object(TenantScopedJWTAuthentication, "get_user") as get_user:
            with self.assertRaises(AuthenticationFailed):
                auth.authenticate(request)
        get_user.assert_not_called()

        request.tenant = SimpleNamespace(slug="acme")
        with mock.patch.object(
            TenantScopedJWTAuthentication, "get_user", return_value=user
        ), mock.patch(
            "horilla_api.authentication.resolve_company_id", return_value=5
        ), mock.patch(
            "horilla_api.authentication.set_selected_company"
        ) as selected:
            result = auth.authenticate(request)
        self.assertEqual(result[0], user)
        selected.assert_called_once_with(5)

    def _default_name(self):
        from django.conf import settings

        return settings.DATABASES["default"]["NAME"]
