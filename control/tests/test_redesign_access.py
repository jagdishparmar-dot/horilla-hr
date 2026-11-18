"""Phase 6 invite state and one-time setup password reveal."""

import os
from unittest import mock

from cryptography.fernet import Fernet
from django.test import Client, RequestFactory, TestCase, override_settings

from control.models import Operator, OperatorAudit, Tenant
from control.setup_access import invite_state, setup_password_matches

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _operator(email):
    operator = Operator(email=email, is_staff=True, is_active=True)
    operator.set_password("correct-horse")
    operator.save()
    return operator


def _tenant(slug, **kwargs):
    tenant = Tenant(
        name=kwargs.pop("name", slug.title()),
        slug=slug,
        status=kwargs.pop("status", Tenant.Status.PROVISIONING),
        admin_name=kwargs.pop("admin_name", ""),
        admin_email=kwargs.pop("admin_email", ""),
    )
    password = kwargs.pop("password", "")
    for key, value in kwargs.items():
        setattr(tenant, key, value)
    if password:
        tenant.set_setup_password(password)
    tenant.save()
    return tenant


@MULTI
class InviteStateTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("access-ops@example.com")
        self.client.post(
            "/control/login/",
            {"email": "access-ops@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_three_invite_states_omit_the_password(self):
        pending = _tenant(
            "pendco",
            admin_name="Ada Lovelace",
            admin_email="ada@pend.test",
            password="pending-secret-value",
        )
        accepted = _tenant(
            "okco",
            status=Tenant.Status.ACTIVE,
            admin_name="Grace Hopper",
            admin_email="grace@ok.test",
        )
        trialing = _tenant(
            "trialco",
            status=Tenant.Status.TRIALING,
            admin_name="Trial Admin",
            admin_email="trial@ok.test",
        )
        missing = _tenant(
            "waitco",
            status=Tenant.Status.SUSPENDED,
            admin_name="Not Yet",
            admin_email="wait@none.test",
        )

        pending_page = self.client.get(f"/control/tenants/{pending.slug}/")
        self.assertContains(pending_page, "Pending")
        self.assertContains(pending_page, "Ada Lovelace")
        self.assertContains(pending_page, "ada@pend.test")
        self.assertContains(pending_page, "Regenerate setup password")
        self.assertNotContains(pending_page, "pending-secret-value")

        accepted_page = self.client.get(f"/control/tenants/{accepted.slug}/")
        self.assertContains(accepted_page, "Accepted")
        self.assertContains(accepted_page, "Grace Hopper")
        self.assertContains(accepted_page, "grace@ok.test")
        self.assertNotContains(accepted_page, "Regenerate setup password")

        trial_page = self.client.get(f"/control/tenants/{trialing.slug}/")
        self.assertContains(trial_page, "Accepted")
        self.assertContains(trial_page, "trial@ok.test")

        missing_page = self.client.get(f"/control/tenants/{missing.slug}/")
        self.assertContains(missing_page, "Not issued")
        self.assertContains(missing_page, "Not Yet")
        self.assertContains(missing_page, "wait@none.test")
        self.assertNotContains(missing_page, "Regenerate setup password")

    def test_regenerate_shows_the_password_once_and_retires_the_old_one(self):
        tenant = _tenant("resetco", password="old-setup-secret", status=Tenant.Status.ACTIVE)
        rotated = self.client.post(f"/control/tenants/{tenant.slug}/setup-password/")
        self.assertEqual(rotated.status_code, 302)
        tenant.refresh_from_db()
        new_password = tenant.setup_password()
        self.assertNotEqual(new_password, "old-setup-secret")
        request = RequestFactory().get("/")
        request.tenant = tenant
        self.assertFalse(setup_password_matches(request, "old-setup-secret"))
        self.assertTrue(setup_password_matches(request, new_password))

        shown = self.client.get(rotated["Location"])
        self.assertContains(shown, new_password)
        self.assertNotContains(shown, "old-setup-secret")
        self.assertContains(shown, "Pending")

        later = self.client.get(f"/control/tenants/{tenant.slug}/")
        self.assertNotContains(later, new_password)

        other = Client(HTTP_HOST="manage.localhost")
        _operator("second-ops@example.com")
        other.post(
            "/control/login/",
            {"email": "second-ops@example.com", "password": "correct-horse"},
        )
        self.assertNotContains(other.get(f"/control/tenants/{tenant.slug}/"), new_password)

        audit = OperatorAudit.objects.get(slug=tenant.slug)
        self.assertEqual(audit.action, OperatorAudit.Action.SETUP_PASSWORD_RESET)
        self.assertEqual(audit.category, OperatorAudit.Category.SECURITY)
        self.assertNotIn(new_password, audit.detail)
        self.assertNotIn("old-setup-secret", audit.detail)

        tenant.setup_password_encrypted = ""
        tenant.save(update_fields=["setup_password_encrypted"])
        cleared = self.client.get(f"/control/tenants/{tenant.slug}/")
        self.assertContains(cleared, "Accepted")
        self.assertNotContains(cleared, "Regenerate setup password")
        refused = self.client.post(f"/control/tenants/{tenant.slug}/setup-password/")
        self.assertEqual(refused.status_code, 302)
        tenant.refresh_from_db()
        self.assertEqual(tenant.setup_password_encrypted, "")
        self.assertEqual(invite_state(tenant), "accepted")
