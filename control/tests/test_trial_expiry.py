"""Scheduled close of lapsed trials. Past-due stays routable. No invoice is issued."""

from datetime import timedelta

from django.test import TestCase
from django.utils import timezone

from control.models import Invoice, Tenant
from control.trials import expire_trials


class TrialExpiryTests(TestCase):
    def test_future_trial_is_unchanged(self):
        ends = timezone.now() + timedelta(days=7)
        tenant = Tenant.objects.create(
            name="Future",
            slug="futureco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=ends,
        )
        self.assertEqual(expire_trials(), 0)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.TRIALING)
        self.assertEqual(tenant.trial_ends_at, ends)

    def test_null_trial_end_stays_trialing(self):
        tenant = Tenant.objects.create(
            name="Open",
            slug="openco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=None,
        )
        self.assertEqual(expire_trials(), 0)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.TRIALING)
        self.assertIsNone(tenant.trial_ends_at)

    def test_past_trial_becomes_past_due_without_an_invoice(self):
        ends = timezone.now() - timedelta(days=1)
        tenant = Tenant.objects.create(
            name="Lapsed",
            slug="lapsedco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=ends,
        )
        self.assertEqual(expire_trials(), 1)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.PAST_DUE)
        self.assertEqual(tenant.trial_ends_at, ends)
        self.assertEqual(Invoice.objects.count(), 0)

    def test_second_pass_leaves_an_already_past_due_trial(self):
        ends = timezone.now() - timedelta(hours=1)
        tenant = Tenant.objects.create(
            name="Twice",
            slug="twiceco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=ends,
        )
        self.assertEqual(expire_trials(), 1)
        self.assertEqual(expire_trials(), 0)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.PAST_DUE)
        self.assertEqual(tenant.trial_ends_at, ends)

    def test_active_tenant_with_an_old_trial_end_stays_active(self):
        ends = timezone.now() - timedelta(days=30)
        tenant = Tenant.objects.create(
            name="Live",
            slug="liveco",
            status=Tenant.Status.ACTIVE,
            trial_ends_at=ends,
        )
        self.assertEqual(expire_trials(), 0)
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)
        self.assertEqual(tenant.trial_ends_at, ends)
