"""Phase 4 billing ledger. Invoices live in the control database only."""

import csv
import os
from datetime import timedelta
from io import StringIO
from unittest import mock

from cryptography.fernet import Fernet
from django.http import HttpResponse
from django.test import Client, RequestFactory, TestCase, override_settings
from django.utils import timezone

from control.billing import (
    BillingError,
    invoice_amount,
    issue_invoice,
    mark_paid,
    mark_past_due,
    void_invoice,
)
from control.middleware import TenantMiddleware
from control.models import Domain, Invoice, Operator, OperatorAudit, Plan, Tenant
from control.pricing import quote
from control.router import TenantRouter
from horilla.scheduling import register_job, run_registered_job

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _tenant(slug, **kwargs):
    plan = kwargs.pop("plan", "starter")
    tenant = Tenant(
        name=kwargs.pop("name", slug.title()),
        slug=slug,
        status=kwargs.pop("status", Tenant.Status.ACTIVE),
        cadence=kwargs.pop("cadence", Tenant.Cadence.MONTHLY),
        seat_limit=kwargs.pop("seat_limit", 10),
        plan_fk=Plan.objects.get(code=plan),
    )
    for key, value in kwargs.items():
        setattr(tenant, key, value)
    tenant.save()
    return tenant


@MULTI
class InvoiceModelTests(TestCase):
    def test_invoice_stays_on_the_control_database_and_matches_the_monthly_quote(self):
        router = TenantRouter()
        self.assertFalse(router.allow_migrate("tenant_acme", "control", "invoice"))
        self.assertTrue(router.allow_migrate("default", "control", "invoice"))
        tenant = _tenant("billco")
        priced = quote("starter", "monthly", 10, [])
        self.assertEqual(invoice_amount(tenant), priced.total_monthly)
        operator = Operator(email="ledger@example.com", is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        invoice = issue_invoice(tenant, operator)
        self.assertEqual(invoice.amount_rupees, priced.total_monthly)
        self.assertEqual(invoice.status, Invoice.Status.OPEN)
        self.assertEqual(invoice.due_on, invoice.issued_on + timedelta(days=14))
        self.assertEqual(invoice.plan_code, "starter")
        self.assertEqual(invoice.seat_count, 10)
        self.assertFalse(hasattr(invoice, "card"))

    def test_only_the_first_invoice_includes_the_setup_fee(self):
        tenant = _tenant("setupco")
        plan = tenant.plan_fk
        plan.setup_fee_rupees = 5000
        plan.save(update_fields=["setup_fee_rupees"])
        priced = quote(plan.code, tenant.cadence, tenant.seat_limit, [])
        operator = Operator(email="setup@example.com", is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        first = issue_invoice(tenant, operator)
        second = issue_invoice(tenant, operator)
        self.assertEqual(first.amount_rupees, priced.term + plan.setup_fee_rupees)
        self.assertEqual(second.amount_rupees, priced.term)


@MULTI
class IssueInvoiceTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        operator = Operator(email="issue@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.operator = operator
        self.client.post(
            "/control/login/",
            {"email": "issue@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        self._env.stop()
        super().tearDown()

    def test_convert_issues_one_invoice_and_a_second_click_does_not(self):
        tenant = _tenant(
            "trialco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=timezone.now() + timedelta(days=7),
        )
        first = self.client.post("/control/tenants/trialco/convert/")
        self.assertEqual(first.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 1)
        self.assertTrue(
            OperatorAudit.objects.filter(
                slug="trialco", action=OperatorAudit.Action.INVOICE_ISSUE
            ).exists()
        )
        second = self.client.post("/control/tenants/trialco/convert/")
        self.assertEqual(second.status_code, 400)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 1)

    def test_quota_save_does_not_issue_an_invoice(self):
        tenant = _tenant("quotaco")
        response = self.client.post(
            "/control/tenants/quotaco/quota/",
            {
                "seat_limit": tenant.seat_limit,
                "storage_limit_gb": tenant.storage_limit_gb,
                "module_employee_records": "on",
                "module_payroll_engine": "on",
                "module_performance_reviews": "on",
            },
        )
        self.assertEqual(response.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 0)

    def test_subscription_change_issues_an_invoice_and_an_unchanged_save_does_not(self):
        tenant = _tenant("subco")
        same = self.client.post(
            "/control/tenants/subco/subscription/",
            {"plan": "starter"},
        )
        self.assertEqual(same.status_code, 302)
        self.assertEqual(Invoice.objects.filter(tenant=tenant).count(), 0)
        changed = self.client.post(
            "/control/tenants/subco/subscription/",
            {"plan": "growth"},
        )
        self.assertEqual(changed.status_code, 302)
        invoice = Invoice.objects.get(tenant=tenant)
        tenant.refresh_from_db()
        self.assertEqual(invoice.plan_code, "growth")
        self.assertEqual(invoice.cadence, "monthly")
        self.assertEqual(invoice.amount_rupees, invoice_amount(tenant))
        self.assertEqual(invoice.status, Invoice.Status.OPEN)


@MULTI
class PastDueTests(TestCase):
    def setUp(self):
        super().setUp()
        self.operator = Operator(email="due@example.com", is_active=True)
        self.operator.set_password("correct-horse")
        self.operator.save()

    def tearDown(self):
        from django.db import connections

        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        super().tearDown()

    def _open(self, slug):
        tenant = _tenant(slug)
        return issue_invoice(tenant, self.operator), tenant

    def test_payment_changes_are_audited_without_secrets(self):
        invoice, tenant = self._open("auditco")
        mark_past_due(invoice, self.operator)
        mark_paid(invoice, self.operator)
        past_due = OperatorAudit.objects.get(
            slug="auditco", action=OperatorAudit.Action.INVOICE_PAST_DUE
        )
        paid = OperatorAudit.objects.get(
            slug="auditco", action=OperatorAudit.Action.INVOICE_PAID
        )
        self.assertEqual(past_due.category, OperatorAudit.Category.BILLING)
        self.assertEqual(paid.category, OperatorAudit.Category.BILLING)
        self.assertIn(str(invoice.pk), paid.detail)
        self.assertNotIn("postgres://", paid.detail)
        self.assertNotIn("correct-horse", paid.detail)
        self.assertEqual(tenant.slug, "auditco")

    def test_one_overdue_invoice_returns_the_tenant_to_active_when_paid(self):
        invoice, tenant = self._open("oneco")
        mark_past_due(invoice)
        invoice.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(invoice.status, Invoice.Status.PAST_DUE)
        self.assertEqual(tenant.status, Tenant.Status.PAST_DUE)
        mark_paid(invoice)
        invoice.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(invoice.status, Invoice.Status.PAID)
        self.assertIsNotNone(invoice.paid_on)
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)

    def test_paying_one_of_two_overdue_invoices_leaves_the_tenant_past_due(self):
        first, tenant = self._open("twoco")
        second = issue_invoice(tenant, self.operator)
        mark_past_due(first)
        mark_past_due(second)
        mark_paid(first)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.PAST_DUE)
        mark_paid(second)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)

    def test_voiding_the_only_past_due_invoice_sets_the_tenant_active(self):
        invoice, tenant = self._open("voidco")
        mark_past_due(invoice)
        void_invoice(invoice, self.operator)
        invoice.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(invoice.status, Invoice.Status.VOID)
        self.assertIsNotNone(invoice.voided_on)
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)
        self.assertTrue(
            OperatorAudit.objects.filter(
                slug="voidco", action=OperatorAudit.Action.INVOICE_VOID
            ).exists()
        )

    def test_mark_past_due_on_a_paid_invoice_does_not_change_the_tenant(self):
        invoice, tenant = self._open("staleco")
        mark_paid(invoice)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)
        invoice.status = Invoice.Status.OPEN
        with self.assertRaises(BillingError):
            mark_past_due(invoice)
        invoice.refresh_from_db()
        tenant.refresh_from_db()
        self.assertEqual(invoice.status, Invoice.Status.PAID)
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)

    def test_a_paid_invoice_cannot_be_voided(self):
        invoice, tenant = self._open("paidco")
        mark_paid(invoice)
        with self.assertRaises(BillingError):
            void_invoice(invoice, self.operator)
        invoice.refresh_from_db()
        self.assertEqual(invoice.status, Invoice.Status.PAID)
        self.assertFalse(
            OperatorAudit.objects.filter(action=OperatorAudit.Action.INVOICE_VOID).exists()
        )

    def test_past_due_host_stays_routable(self):
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.addCleanup(self._env.stop)
        tenant = _tenant("duehost", status=Tenant.Status.PAST_DUE)
        tenant.set_db_password("db-secret")
        tenant.save()
        Domain.objects.create(
            tenant=tenant, host="duehost.localhost", is_primary=True, verified=True
        )
        seen = []

        def get_response(request):
            seen.append(request.tenant.slug)
            return HttpResponse("ok")

        with mock.patch(
            "control.middleware.ensure_tenant_connection",
            return_value="tenant_duehost",
        ):
            response = TenantMiddleware(get_response)(
                RequestFactory().get("/", HTTP_HOST="duehost.localhost")
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(seen, ["duehost"])

        slugs = []

        def marker():
            return None

        register_job(marker, "interval", job_id="phase4.billing.marker", minutes=5)

        def connect(row):
            slugs.append(row.slug)
            return f"tenant_{row.slug}"

        with mock.patch("control.db.ensure_tenant_connection", side_effect=connect):
            run_registered_job("phase4.billing.marker")
        self.assertIn("duehost", slugs)


@MULTI
class BillingPageTests(TestCase):
    def setUp(self):
        super().setUp()
        self.client = Client(HTTP_HOST="manage.localhost")
        operator = Operator(email="page@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.operator = operator
        self.client.post(
            "/control/login/",
            {"email": "page@example.com", "password": "correct-horse"},
        )

    def test_paid_filter_hides_open_rows_and_csv_uses_whole_rupees(self):
        open_tenant = _tenant("opencsv")
        paid_tenant = _tenant("paidcsv")
        open_invoice = issue_invoice(open_tenant, self.operator)
        paid_invoice = issue_invoice(paid_tenant, self.operator)
        mark_paid(paid_invoice)
        page = self.client.get("/control/billing/?status=paid")
        self.assertContains(page, "paidcsv")
        self.assertNotContains(page, "opencsv")
        self.assertContains(page, str(paid_invoice.amount_rupees))
        self.assertContains(
            page,
            f'<span class="control-nav-count control-nav-count-trial">{1}</span>',
            html=True,
        )
        exported = self.client.get("/control/billing/export.csv?status=paid")
        self.assertEqual(exported.status_code, 200)
        rows = list(csv.reader(StringIO(exported.content.decode())))
        self.assertEqual(
            rows[0],
            [
                "invoice_id",
                "tenant_slug",
                "period",
                "plan",
                "seats",
                "amount_rupees",
                "status",
                "issued",
                "due",
            ],
        )
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[1][0], str(paid_invoice.pk))
        self.assertEqual(rows[1][1], "paidcsv")
        self.assertEqual(rows[1][5], str(paid_invoice.amount_rupees))
        self.assertEqual(rows[1][6], "paid")
        self.assertNotIn(".", rows[1][5])
        self.assertNotEqual(rows[1][0], str(open_invoice.pk))

    def test_billing_badge_is_hidden_when_nothing_is_open(self):
        page = self.client.get("/control/billing/")
        self.assertEqual(page.context["nav_billing_count"], 0)
        self.assertNotContains(page, "control-nav-count-trial")
