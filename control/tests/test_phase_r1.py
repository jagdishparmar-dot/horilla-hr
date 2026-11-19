"""Phase R1: operator lockout, password rules, and staff gates."""

import os
from datetime import date
from unittest import mock

from cryptography.fernet import Fernet
from django.core.cache import cache
from django.test import Client, TestCase, override_settings

from control.auth import SESSION_VERSION
from control.context import activate_tenant_alias, clear_tenant_alias
from control.forms import OperatorCreateForm, OperatorPasswordForm
from control.lockout import (
    LOCKED_MESSAGE,
    _lock_key,
    cooldown_for_strikes,
    is_locked,
    record_failure,
)
from control.models import Addon, Invoice, Operator, OperatorAudit, Plan, Tenant
from horilla.isolation import activate_cache_scope, clear_cache_scope

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
    CACHES={
        "default": {
            "BACKEND": "django.core.cache.backends.locmem.LocMemCache",
            "LOCATION": "phase-r1",
            "KEY_PREFIX": "horilla",
            "KEY_FUNCTION": "horilla.cache.tenant_cache_key",
        }
    },
)


def _operator(email, password="correct-horse", *, staff=True, active=True):
    operator = Operator(email=email, is_staff=staff, is_active=active)
    operator.set_password(password)
    operator.save()
    return operator


@MULTI
class LockoutTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.addCleanup(self._env.stop)
        cache.clear()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("ops@example.com")

    def _control_get(self, key):
        token = activate_cache_scope("control")
        try:
            return cache.get(key)
        finally:
            clear_cache_scope(token)

    def test_sixth_failure_skips_the_password_hash_and_a_correct_password_stays_out(self):
        calls = {"n": 0}
        original = Operator.check_password

        def spy(self, raw):
            calls["n"] += 1
            return original(self, raw)

        secret = "correct-horse"
        with mock.patch.object(Operator, "check_password", spy):
            for _ in range(5):
                failed = self.client.post(
                    "/control/login/",
                    {"email": "ops@example.com", "password": "wrong-password"},
                )
                self.assertEqual(failed.status_code, 200)
            self.assertEqual(calls["n"], 5)
            locked = self.client.post(
                "/control/login/",
                {"email": "ops@example.com", "password": secret},
            )
        self.assertEqual(calls["n"], 5)
        self.assertEqual(locked.status_code, 200)
        self.assertContains(locked, LOCKED_MESSAGE)
        self.assertNotIn("control_sessionid", locked.cookies)
        self.assertNotIn(secret, locked.content.decode())

    def test_failed_and_successful_logins_are_audited_without_the_password(self):
        typed_password = "wrong-password"
        self.client.post(
            "/control/login/",
            {"email": "ops@example.com", "password": typed_password},
        )
        failed = OperatorAudit.objects.get(
            action=OperatorAudit.Action.OPERATOR_LOGIN_FAILED
        )
        self.assertEqual(failed.category, OperatorAudit.Category.SECURITY)
        self.assertEqual(failed.operator, self.operator)
        self.assertIn("ops@example.com", failed.detail)
        self.assertIn("127.0.0.1", failed.detail)
        self.assertNotIn(typed_password, failed.detail)

        unknown = self.client.post(
            "/control/login/",
            {"email": "nobody@example.com", "password": typed_password},
        )
        self.assertContains(unknown, "Email or password is not valid.")
        self.assertNotContains(unknown, "does not exist")
        missing = OperatorAudit.objects.filter(
            action=OperatorAudit.Action.OPERATOR_LOGIN_FAILED,
            operator__isnull=True,
        ).get()
        self.assertIn("nobody@example.com", missing.detail)
        self.assertNotIn(typed_password, missing.detail)

        signed_in = self.client.post(
            "/control/login/",
            {"email": "ops@example.com", "password": "correct-horse"},
        )
        self.assertEqual(signed_in.status_code, 302)
        logged = OperatorAudit.objects.get(action=OperatorAudit.Action.OPERATOR_LOGIN)
        self.assertEqual(logged.category, OperatorAudit.Category.SECURITY)
        self.assertNotIn("correct-horse", logged.detail)
        page = self.client.get("/control/audit/?category=security")
        self.assertContains(page, "operator_login")
        self.assertContains(page, "operator_login_failed")

    def test_lock_counters_live_under_the_control_cache_prefix(self):
        email, ip = "ops@example.com", "203.0.113.9"
        for _ in range(5):
            record_failure(email, ip, now=1_000_000)
        self.assertTrue(is_locked(email, ip, now=1_000_000 + 1))
        self.assertIsNotNone(self._control_get(_lock_key(email, ip)))
        alias = activate_tenant_alias("tenant_acme")
        try:
            self.assertIsNone(cache.get(_lock_key(email, ip)))
        finally:
            clear_tenant_alias(alias)

    def test_repeat_lockouts_double_the_cooldown(self):
        email, ip = "ops@example.com", "203.0.113.8"
        start = 2_000_000.0
        for _ in range(5):
            record_failure(email, ip, now=start)
        self.assertEqual(
            self._control_get(_lock_key(email, ip)), start + cooldown_for_strikes(1)
        )
        token = activate_cache_scope("control")
        try:
            cache.delete(_lock_key(email, ip))
        finally:
            clear_cache_scope(token)
        later = start + 10
        for _ in range(5):
            record_failure(email, ip, now=later)
        self.assertEqual(
            self._control_get(_lock_key(email, ip)), later + cooldown_for_strikes(2)
        )
        self.assertEqual(cooldown_for_strikes(2), cooldown_for_strikes(1) * 2)


@MULTI
class PasswordRuleTests(TestCase):
    def test_common_and_email_like_passwords_are_rejected(self):
        common = OperatorCreateForm(
            data={
                "email": "ada@example.com",
                "password": "password123",
                "is_staff": "",
            }
        )
        self.assertFalse(common.is_valid())
        self.assertIn("too common", common.errors["password"][0])

        similar = OperatorCreateForm(
            data={
                "email": "stallion@example.com",
                "password": "stallion",
                "is_staff": "",
            }
        )
        self.assertFalse(similar.is_valid())
        self.assertIn("too similar", similar.errors["password"][0])

        strong = OperatorCreateForm(
            data={
                "email": "ada@example.com",
                "password": "correct-horse-battery",
                "is_staff": "",
            }
        )
        self.assertTrue(strong.is_valid())

    def test_change_form_uses_the_same_rules_and_checks_the_current_password(self):
        operator = _operator("ada@example.com")
        wrong = OperatorPasswordForm(
            operator,
            data={"current_password": "nope-nope", "new_password": "correct-horse-battery"},
        )
        self.assertFalse(wrong.is_valid())
        self.assertIn("not valid", wrong.errors["current_password"][0])
        common = OperatorPasswordForm(
            operator,
            data={"current_password": "correct-horse", "new_password": "password123"},
        )
        self.assertFalse(common.is_valid())
        self.assertIn("too common", common.errors["new_password"][0])


@MULTI
class StaffGateTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.addCleanup(self._env.stop)
        cache.clear()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("clerk@example.com", staff=False)
        self.tenant = Tenant.objects.create(
            name="Gate", slug="gateco", status=Tenant.Status.ACTIVE
        )
        self.plan = Plan.objects.create(code="gate", name="Gate", monthly_price=100)
        self.addon = Addon.objects.create(code="extra", name="Extra", amount=10)
        today = date(2026, 11, 19)
        self.invoice = Invoice.objects.create(
            tenant=self.tenant,
            plan_code="gate",
            cadence=Tenant.Cadence.MONTHLY,
            seat_count=1,
            amount_rupees=100,
            status=Invoice.Status.OPEN,
            period_label="November 2026",
            issued_on=today,
            due_on=today,
        )
        self.client.post(
            "/control/login/",
            {"email": "clerk@example.com", "password": "correct-horse"},
        )

    def test_non_staff_gets_403_on_every_gated_route_and_does_not_see_the_buttons(self):
        posts = [
            f"/control/tenants/{self.tenant.slug}/delete/",
            f"/control/tenants/{self.tenant.slug}/remove/",
            f"/control/tenants/{self.tenant.slug}/restore/",
            f"/control/tenants/{self.tenant.slug}/setup-password/",
            "/control/plans/new/",
            f"/control/plans/{self.plan.code}/edit/",
            f"/control/plans/{self.plan.code}/delete/",
            "/control/plans/addons/new/",
            f"/control/plans/addons/{self.addon.code}/edit/",
            f"/control/plans/addons/{self.addon.code}/delete/",
            f"/control/billing/invoices/{self.invoice.pk}/past-due/",
            f"/control/billing/invoices/{self.invoice.pk}/paid/",
            f"/control/billing/invoices/{self.invoice.pk}/void/",
        ]
        for path in posts:
            response = self.client.post(path, {"confirm_slug": self.tenant.slug})
            self.assertEqual(response.status_code, 403, path)
        for path in (
            "/control/plans/new/",
            f"/control/plans/{self.plan.code}/edit/",
            "/control/plans/addons/new/",
            f"/control/plans/addons/{self.addon.code}/edit/",
        ):
            self.assertEqual(self.client.get(path).status_code, 403, path)

        detail = self.client.get(f"/control/tenants/{self.tenant.slug}/")
        self.assertEqual(detail.status_code, 200)
        self.assertNotContains(detail, "Queue delete")
        self.assertNotContains(detail, "Queue restore")
        self.assertNotContains(detail, "Regenerate setup password")
        self.assertNotContains(detail, "Remove tenant")
        plans = self.client.get("/control/plans/")
        self.assertNotContains(plans, "New plan")
        self.assertNotContains(plans, "New add-on")
        billing = self.client.get("/control/billing/")
        self.assertNotContains(billing, "Mark paid")
        self.assertNotContains(billing, ">Void</button>")

        # Day-to-day actions stay open to a non-staff operator.
        suspend = self.client.post(
            f"/control/tenants/{self.tenant.slug}/suspend/",
            {"reason": "pause"},
        )
        self.assertNotEqual(suspend.status_code, 403)


@MULTI
class OperatorAccountTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.addCleanup(self._env.stop)
        cache.clear()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("ops@example.com")
        self.client.post(
            "/control/login/",
            {"email": "ops@example.com", "password": "correct-horse"},
        )

    def test_reactivate_restores_login_and_is_audited(self):
        target = _operator("old@example.com", active=False)
        page = self.client.get("/control/operators/")
        self.assertContains(page, "Reactivate")
        response = self.client.post(f"/control/operators/{target.pk}/reactivate/")
        self.assertEqual(response.status_code, 302)
        target.refresh_from_db()
        self.assertTrue(target.is_active)
        audit = OperatorAudit.objects.get(
            action=OperatorAudit.Action.OPERATOR_REACTIVATE
        )
        self.assertEqual(audit.category, OperatorAudit.Category.SECURITY)
        self.assertIn("old@example.com", audit.detail)
        self.assertNotIn("correct-horse", audit.detail)

        other = Client(HTTP_HOST="manage.localhost")
        signed_in = other.post(
            "/control/login/",
            {"email": "old@example.com", "password": "correct-horse"},
        )
        self.assertEqual(signed_in.status_code, 302)

    def test_password_change_signs_out_other_sessions_and_keeps_this_one(self):
        other = Client(HTTP_HOST="manage.localhost")
        other.post(
            "/control/login/",
            {"email": "ops@example.com", "password": "correct-horse"},
        )
        self.assertEqual(other.get("/control/").status_code, 200)
        before = self.client.cookies["control_sessionid"].value
        new_password = "correct-horse-battery"
        changed = self.client.post(
            "/control/operators/password/",
            {"current_password": "correct-horse", "new_password": new_password},
        )
        self.assertEqual(changed.status_code, 302)
        self.assertNotEqual(self.client.cookies["control_sessionid"].value, before)
        self.operator.refresh_from_db()
        self.assertEqual(self.operator.session_version, 1)
        from django.conf import settings
        from importlib import import_module

        store = import_module(settings.SESSION_ENGINE).SessionStore(
            self.client.cookies["control_sessionid"].value
        )
        self.assertEqual(store.get(SESSION_VERSION), self.operator.session_version)
        self.assertEqual(self.client.get("/control/").status_code, 200)
        self.assertEqual(other.get("/control/").status_code, 302)
        self.operator.refresh_from_db()
        self.assertTrue(self.operator.check_password(new_password))
        audit = OperatorAudit.objects.get(
            action=OperatorAudit.Action.OPERATOR_PASSWORD_CHANGE
        )
        self.assertNotIn(new_password, audit.detail)
        self.assertNotIn("correct-horse", audit.detail)
        self.assertEqual(audit.detail, "Changed own password.")
