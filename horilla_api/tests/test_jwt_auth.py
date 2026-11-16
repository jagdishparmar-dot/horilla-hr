"""Horilla API JWT login and auth-gate smoke tests."""

import base64

from django.test import Client, TestCase
from rest_framework.test import APIClient

from horilla.testkit import make_company, make_employee, make_user


class LoginAPITests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.company = make_company("API Co")
        self.password = "secret123"
        self.user = make_user("api_login", password=self.password)
        self.employee = make_employee(
            company=self.company,
            email="api_login@test.horilla",
            user=self.user,
        )

    def test_login_returns_access_token(self):
        response = self.client.post(
            "/api/auth/login/",
            {"username": "api_login", "password": self.password},
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.assertIn("access", response.data)
        self.assertTrue(response.data["access"])
        self.assertEqual(response.data["employee"]["id"], self.employee.pk)


class JWTProtectedEndpointTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        company = make_company("API Gate")
        self.password = "secret123"
        self.user = make_user("api_gate", password=self.password)
        make_employee(
            company=company,
            email="api_gate@test.horilla",
            user=self.user,
        )

    def test_unauthenticated_gets_401(self):
        response = self.client.get("/api/employee/employee-type/")
        self.assertEqual(response.status_code, 401)

    def test_jwt_allows_access(self):
        login = self.client.post(
            "/api/auth/login/",
            {"username": "api_gate", "password": self.password},
            format="json",
        )
        token = login.data["access"]
        self.client.credentials(HTTP_AUTHORIZATION=f"Bearer {token}")
        response = self.client.get("/api/employee/employee-type/")
        self.assertEqual(response.status_code, 200)


class RejectBasicAuthTests(TestCase):
    def test_basic_auth_does_not_authenticate_api(self):
        """Basic credentials must not unlock JWT-only endpoints."""
        client = Client()
        creds = base64.b64encode(b"user:pass").decode("ascii")
        response = client.get(
            "/api/employee/employee-type/",
            HTTP_AUTHORIZATION=f"Basic {creds}",
        )
        self.assertEqual(response.status_code, 401)


class PasswordResetAPITests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.password = "secret123"
        self.user = make_user("api_reset", password=self.password)

    def test_unauthenticated_reset_gets_401(self):
        response = self.client.post(
            "/api/auth/reset-password/",
            {
                "old_password": self.password,
                "new_password": "newsecret1",
                "confirm_password": "newsecret1",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 401)

    def test_wrong_old_password_gets_400(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            "/api/auth/reset-password/",
            {
                "old_password": "wrong-old",
                "new_password": "newsecret1",
                "confirm_password": "newsecret1",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 400)
        self.assertIn("old_password", response.data)

    def test_successful_password_reset(self):
        self.client.force_authenticate(user=self.user)
        response = self.client.post(
            "/api/auth/reset-password/",
            {
                "old_password": self.password,
                "new_password": "newsecret99",
                "confirm_password": "newsecret99",
            },
            format="json",
        )
        self.assertEqual(response.status_code, 200)
        self.user.refresh_from_db()
        self.assertTrue(self.user.check_password("newsecret99"))


class ForgotPasswordAPITests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.company = make_company("Forgot Co")
        self.user = make_user("forgot_me", password="secret123")
        self.employee = make_employee(
            company=self.company,
            email="forgot_me@test.horilla",
            user=self.user,
        )

    def _post(self, payload, send_mail=None, backend=None):
        from unittest.mock import MagicMock, patch

        from base.forms import PassWordResetForm

        mail = send_mail if send_mail is not None else MagicMock()
        mail_backend = backend if backend is not None else MagicMock()
        if not hasattr(mail_backend, "configuration"):
            mail_backend.configuration = object()
        if not hasattr(mail_backend, "dynamic_from_email_with_display_name"):
            mail_backend.dynamic_from_email_with_display_name = "hr@test.horilla"
        with patch(
            "horilla_api.api_views.auth.views.ConfiguredEmailBackend",
            return_value=mail_backend,
        ):
            with patch.object(PassWordResetForm, "send_mail", mail):
                return self.client.post(
                    "/api/v1/auth/forgot-password/",
                    payload,
                    format="json",
                ), mail

    def test_sends_reset_mail_for_username(self):
        response, mail = self._post({"email": "forgot_me"})
        self.assertEqual(response.status_code, 200)
        self.assertIn("***@", response.data["message"])
        self.assertIn("test.horilla", response.data["message"])
        self.assertTrue(mail.called)
        context = None
        args, kwargs = mail.call_args
        context = kwargs.get("context")
        if context is None:
            for arg in args:
                if isinstance(arg, dict) and "reset_url" in arg:
                    context = arg
                    break
        self.assertIsNotNone(context)
        self.assertIn("/reset/", context["reset_url"])

    def test_sends_reset_mail_for_email_address(self):
        response, mail = self._post({"email": "forgot_me@test.horilla"})
        self.assertEqual(response.status_code, 200)
        self.assertTrue(mail.called)

    def test_unknown_account_is_400(self):
        response, mail = self._post({"email": "nobody"})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(mail.called)
        self.assertIn("No account found", response.data["error"])

    def test_empty_identifier_is_400(self):
        response, mail = self._post({"email": "  "})
        self.assertEqual(response.status_code, 400)
        self.assertFalse(mail.called)

    def test_unconfigured_mail_server_is_400(self):
        from unittest.mock import MagicMock

        backend = MagicMock()
        backend.configuration = None
        response, mail = self._post({"email": "forgot_me"}, backend=backend)
        self.assertEqual(response.status_code, 400)
        self.assertFalse(mail.called)
        self.assertIn("mail server", response.data["error"].lower())
