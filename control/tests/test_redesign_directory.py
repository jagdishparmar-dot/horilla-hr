import os
from datetime import timedelta
from unittest import mock

from cryptography.fernet import Fernet
from django.http import HttpResponse
from django.test import Client, RequestFactory, TestCase, override_settings
from django.utils import timezone

from control.middleware import TenantMiddleware
from control.models import Invoice, Operator, OperatorAudit, Plan, ProvisionJob, Tenant
from control.provisioning import (
    TRIAL_DAYS,
    enqueue_create,
    enqueue_resume,
    enqueue_suspend,
    process_available_jobs,
    seed_tenant,
)
from control.views import directory_queryset
from horilla.scheduling import register_job, run_registered_job

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _patch_create_sql():
    names = [
        "_step_create_role",
        "_step_create_database",
        "_step_revoke_public",
        "_step_grant_connect",
        "_step_revoke_other_roles",
        "_step_store_connection",
        "_step_migrate",
        "_step_seed",
    ]
    return [mock.patch(f"control.provisioning.{name}") for name in names]


@MULTI
class DirectoryTrialTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        operator = Operator(email="directory@example.com", is_staff=True, is_active=True)
        operator.set_password("correct-horse")
        operator.save()
        self.operator = operator
        self.client.post(
            "/control/login/",
            {"email": "directory@example.com", "password": "correct-horse"},
        )

    def tearDown(self):
        from django.db import connections

        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        self._env.stop()
        super().tearDown()

    def _run_create(self, **kwargs):
        patches = _patch_create_sql()
        for item in patches:
            item.start()
        try:
            payload = {"name": "Trial Co", "slug": "trialco", "plan": "growth"}
            payload.update(kwargs)
            job = enqueue_create(**payload)
            process_available_jobs()
        finally:
            for item in patches:
                item.stop()
        job.refresh_from_db()
        job.tenant.refresh_from_db()
        return job

    def test_trial_flag_sets_trialing_and_a_plain_create_stays_active(self):
        trial = self._run_create(start_as_trial=True)
        self.assertEqual(trial.tenant.status, Tenant.Status.TRIALING)
        self.assertEqual(
            trial.tenant.trial_ends_at,
            trial.tenant.activated_at + timedelta(days=TRIAL_DAYS),
        )
        plain = self._run_create(name="Live Co", slug="liveco", start_as_trial=False)
        self.assertEqual(plain.tenant.status, Tenant.Status.ACTIVE)
        self.assertIsNone(plain.tenant.trial_ends_at)

    def test_scheduler_loop_includes_trialing(self):
        Tenant.objects.create(name="Live", slug="liveco", status=Tenant.Status.ACTIVE)
        Tenant.objects.create(name="Trial", slug="trialco", status=Tenant.Status.TRIALING)
        Tenant.objects.create(name="Paused", slug="paused", status=Tenant.Status.SUSPENDED)
        seen = []

        def marker():
            return None

        register_job(marker, "interval", job_id="phase3.directory.marker", minutes=5)

        def connect(tenant):
            seen.append(tenant.slug)
            return f"tenant_{tenant.slug}"

        with mock.patch("control.db.ensure_tenant_connection", side_effect=connect):
            run_registered_job("phase3.directory.marker")
        self.assertEqual(seen, ["liveco", "trialco"])

    def test_trialing_host_is_routable(self):
        tenant = Tenant(name="Trial", slug="trialco", status=Tenant.Status.TRIALING)
        tenant.set_db_password("db-secret")
        tenant.save()
        from control.models import Domain

        Domain.objects.create(
            tenant=tenant, host="trialco.localhost", is_primary=True, verified=True
        )
        seen = []

        def get_response(request):
            seen.append(getattr(request, "tenant", None) and request.tenant.slug)
            return HttpResponse("ok")

        response = TenantMiddleware(get_response)(
            RequestFactory().get("/", HTTP_HOST="trialco.localhost")
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(seen, ["trialco"])

    def test_convert_is_only_for_a_trial(self):
        trial = Tenant.objects.create(
            name="Trial",
            slug="trialco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=timezone.now() + timedelta(days=14),
        )
        active = Tenant.objects.create(name="Live", slug="liveco", status=Tenant.Status.ACTIVE)
        page = self.client.get("/control/tenants/trialco/")
        self.assertContains(page, "Convert to active")
        active_page = self.client.get("/control/tenants/liveco/")
        self.assertNotContains(active_page, "Convert to active")
        rejected = self.client.post("/control/tenants/liveco/convert/")
        self.assertEqual(rejected.status_code, 400)
        active.refresh_from_db()
        self.assertEqual(active.status, Tenant.Status.ACTIVE)
        self.assertFalse(OperatorAudit.objects.filter(slug="liveco").exists())
        before_jobs = ProvisionJob.objects.count()
        converted = self.client.post("/control/tenants/trialco/convert/")
        self.assertEqual(converted.status_code, 302)
        trial.refresh_from_db()
        self.assertEqual(trial.status, Tenant.Status.ACTIVE)
        self.assertIsNone(trial.trial_ends_at)
        audit = OperatorAudit.objects.get(slug="trialco", action=OperatorAudit.Action.TRIAL_CONVERT)
        self.assertEqual(audit.operator, self.operator)
        self.assertEqual(ProvisionJob.objects.count(), before_jobs)

    def test_suspend_requires_a_reason_and_resume_clears_it(self):
        tenant = Tenant.objects.create(name="Live", slug="liveco", status=Tenant.Status.ACTIVE)
        empty = self.client.post("/control/tenants/liveco/suspend/", {"reason": "   "})
        self.assertEqual(empty.status_code, 400)
        self.assertEqual(tenant.jobs.count(), 0)
        queued = self.client.post(
            "/control/tenants/liveco/suspend/",
            {"reason": "Billing review"},
        )
        self.assertEqual(queued.status_code, 302)
        job = tenant.jobs.get(kind=ProvisionJob.Kind.SUSPEND)
        self.assertEqual(job.payload["suspension_reason"], "Billing review")
        process_available_jobs()
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.SUSPENDED)
        self.assertEqual(tenant.suspension_reason, "Billing review")
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(tenant)
            process_available_jobs()
        tenant.refresh_from_db()
        self.assertEqual(tenant.status, Tenant.Status.ACTIVE)
        self.assertEqual(tenant.suspension_reason, "")

        trial = Tenant.objects.create(
            name="Trial",
            slug="trialco",
            status=Tenant.Status.TRIALING,
            trial_ends_at=timezone.now() + timedelta(days=3),
        )
        enqueue_suspend(trial, "Pause the trial")
        process_available_jobs()
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(trial)
            process_available_jobs()
        trial.refresh_from_db()
        self.assertEqual(trial.status, Tenant.Status.TRIALING)
        self.assertEqual(trial.suspension_reason, "")

        overdue = Tenant.objects.create(
            name="Due",
            slug="dueco",
            status=Tenant.Status.SUSPENDED,
            suspension_reason="collections",
        )
        today = timezone.localdate()
        Invoice.objects.create(
            tenant=overdue,
            plan_code="starter",
            cadence=Tenant.Cadence.MONTHLY,
            seat_count=1,
            amount_rupees=100,
            status=Invoice.Status.PAST_DUE,
            period_label="November 2026",
            issued_on=today,
            due_on=today,
        )
        with mock.patch("control.provisioning._database_exists", return_value=True):
            enqueue_resume(overdue)
            process_available_jobs()
        overdue.refresh_from_db()
        self.assertEqual(overdue.status, Tenant.Status.PAST_DUE)
        self.assertEqual(overdue.suspension_reason, "")

    def test_profile_round_trips_without_creating_a_login(self):
        with mock.patch("horilla_auth.models.HorillaUser.objects.create") as create_user:
            response = self.client.post(
                "/control/tenants/new/",
                {
                    "name": "Northwind Labs",
                    "slug": "northwind",
                    "industry": "Logistics",
                    "admin_name": "Ada Lovelace",
                    "admin_email": "Ada@Example.com",
                    "plan": "starter",
                    "cadence": "annual",
                    "seats": "10",
                    "module_employee_records": "on",
                    "module_payroll_engine": "on",
                    "module_performance_reviews": "on",
                },
            )
        self.assertEqual(response.status_code, 302)
        create_user.assert_not_called()
        self.assertIsNone(seed_tenant(Tenant.objects.get(slug="northwind"), {}))
        tenant = Tenant.objects.get(slug="northwind")
        self.assertEqual(tenant.industry, "Logistics")
        self.assertEqual(tenant.admin_name, "Ada Lovelace")
        self.assertEqual(tenant.admin_email, "ada@example.com")
        detail = self.client.get("/control/tenants/northwind/")
        self.assertContains(detail, "Logistics")
        self.assertContains(detail, "Ada Lovelace")
        self.assertContains(detail, "ada@example.com")

    def test_directory_filters_by_email_and_plan_without_a_tenant_database(self):
        growth = Plan.objects.get(code="growth")
        starter = Plan.objects.get(code="starter")
        Tenant.objects.create(
            name="Alpha",
            slug="alpha",
            status=Tenant.Status.ACTIVE,
            plan_fk=growth,
            admin_email="buyer@alpha.test",
            industry="Retail",
            active_seats=4,
            seat_limit=10,
            used_storage_gb=1,
            storage_limit_gb=4,
        )
        Tenant.objects.create(
            name="Beta",
            slug="beta",
            status=Tenant.Status.TRIALING,
            plan_fk=starter,
            admin_email="other@beta.test",
        )
        matched = list(directory_queryset(query="buyer@alpha.test"))
        self.assertEqual([tenant.slug for tenant in matched], ["alpha"])
        by_plan = list(directory_queryset(plan="starter"))
        self.assertEqual([tenant.slug for tenant in by_plan], ["beta"])
        with mock.patch(
            "control.usage.count_employees",
            side_effect=AssertionError("tenant database opened"),
        ):
            page = self.client.get("/control/?plan=growth")
        self.assertContains(page, "Alpha")
        self.assertNotContains(page, "Beta")
        self.assertContains(page, "Growth")
        self.assertContains(page, "Seats 40%")
        self.assertContains(page, "Storage 25%")
        self.assertContains(page, "Employee records")

    def test_trial_nav_count_matches_the_tab_and_hides_at_zero(self):
        Tenant.objects.create(name="Live", slug="liveco", status=Tenant.Status.ACTIVE)
        quiet = self.client.get("/control/")
        self.assertNotContains(quiet, "control-nav-count-trial")
        self.assertContains(quiet, "Trialing")
        Tenant.objects.create(name="Trial", slug="trialco", status=Tenant.Status.TRIALING)
        page = self.client.get("/control/")
        self.assertContains(page, '<span class="control-nav-count control-nav-count-trial">1</span>', html=True)
        self.assertEqual(page.context["nav_trial_count"], page.context["stats"]["trialing"])
        self.assertEqual(page.context["stats"]["trialing"], 1)
