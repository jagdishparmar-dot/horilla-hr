import os
from datetime import timedelta
from unittest import mock

from cryptography.fernet import Fernet
from django.db import connection, connections
from django.http import HttpResponse, HttpResponseNotFound
from django.test import Client, RequestFactory, TestCase, override_settings
from django.test.utils import CaptureQueriesContext
from django.urls import Resolver404, resolve
from django.utils import timezone

from control.context import clear_tenant_alias
from control.middleware import TenantMiddleware
from control.catalog import plan_code_for_label
from control.models import Domain, Invoice, Operator, OperatorAudit, Plan, ProvisionJob, Tenant
from control.provisioning import ProvisionError

MULTI = override_settings(
    HORILLA_MULTITENANT=True,
    HORILLA_PLATFORM_DOMAIN="localhost",
    HORILLA_DASHBOARD_HOST="manage.localhost",
    ALLOWED_HOSTS=[".localhost", "manage.localhost", "testserver"],
)


def _operator(email, password="correct-horse", *, staff=True, active=True):
    operator = Operator(email=email, is_staff=staff, is_active=active)
    operator.set_password(password)
    operator.save()
    return operator


@MULTI
class RedesignShellTests(TestCase):
    def setUp(self):
        super().setUp()
        self._env = mock.patch.dict(
            os.environ,
            {"TENANT_DB_FERNET_KEY": Fernet.generate_key().decode()},
        )
        self._env.start()
        self.client = Client(HTTP_HOST="manage.localhost")
        self.operator = _operator("ops@example.com")

    def tearDown(self):
        clear_tenant_alias()
        for alias in list(connections.databases):
            if str(alias).startswith("tenant_"):
                connections[alias].close()
                connections.databases.pop(alias, None)
        self._env.stop()
        super().tearDown()

    def _login(self, email="ops@example.com", password="correct-horse"):
        return self.client.post(
            "/control/login/",
            {"email": email, "password": password},
        )

    def _create_tenant(self, slug, *, name=None, status=Tenant.Status.ACTIVE, plan=""):
        tenant = Tenant(
            name=name or slug.title(),
            slug=slug,
            status=status,
            db_name=f"tenant_{slug}",
            db_user=f"tenant_{slug}",
            db_host="db",
            db_port=5432,
        )
        if plan:
            tenant.plan_fk = Plan.objects.get(code=plan_code_for_label(plan))
        tenant.set_db_password("db-secret")
        tenant.save()
        Domain.objects.create(
            tenant=tenant,
            host=f"{slug}.localhost",
            is_primary=True,
            verified=True,
        )
        return tenant

    def test_navigation_destinations_auth_and_tenant_host_isolation(self):
        self._create_tenant("alpha")
        self._create_tenant("bravo", status=Tenant.Status.PROVISIONING)

        for path in ("/control/", "/control/plans/", "/control/billing/", "/control/audit/"):
            anon = self.client.get(path)
            self.assertEqual(anon.status_code, 302)
            self.assertIn("/control/login/", anon["Location"])

        self._login()
        for path, heading in (
            ("/control/", "Tenants"),
            ("/control/plans/", "Plans &amp; Add-ons"),
            ("/control/billing/", "Billing &amp; Ledger"),
            ("/control/audit/", "Audit Log"),
            ("/control/operators/", "Operators"),
        ):
            res = self.client.get(path)
            self.assertEqual(res.status_code, 200)
            self.assertContains(res, heading)
            self.assertContains(res, '<span class="control-nav-count">2</span>', html=True)

        def resolve_on_host(request):
            try:
                resolve(request.path_info, urlconf=request.urlconf)
            except Resolver404:
                return HttpResponseNotFound("missing")
            return HttpResponse("ok")

        middleware = TenantMiddleware(resolve_on_host)
        factory = RequestFactory()
        for path in ("/control/", "/control/plans/", "/control/billing/", "/control/audit/"):
            tenant_res = middleware(factory.get(path, HTTP_HOST="alpha.localhost"))
            self.assertEqual(tenant_res.status_code, 404)
            dash_res = middleware(factory.get(path, HTTP_HOST="manage.localhost"))
            self.assertEqual(dash_res.status_code, 200)

    def test_kpi_strip_figures_and_constant_query_count(self):
        now = timezone.now()
        fresh = self._create_tenant("fresh", status=Tenant.Status.ACTIVE)
        stale = self._create_tenant("stale", status=Tenant.Status.ACTIVE)
        missing = self._create_tenant("missing", status=Tenant.Status.PROVISIONING)
        paused = self._create_tenant("paused", status=Tenant.Status.SUSPENDED)
        dropped = self._create_tenant("dropped", status=Tenant.Status.DELETED)

        ProvisionJob.objects.create(
            tenant=fresh,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
            finished_at=now - timedelta(days=1),
        )
        ProvisionJob.objects.create(
            tenant=stale,
            kind=ProvisionJob.Kind.BACKUP,
            status=ProvisionJob.Status.SUCCEEDED,
            finished_at=now - timedelta(days=9),
        )
        ProvisionJob.objects.create(
            tenant=paused,
            kind=ProvisionJob.Kind.MIGRATE,
            status=ProvisionJob.Status.FAILED,
            finished_at=now - timedelta(days=2),
        )
        ProvisionJob.objects.create(
            tenant=missing,
            kind=ProvisionJob.Kind.CREATE,
            status=ProvisionJob.Status.FAILED,
            finished_at=now - timedelta(days=10),
        )
        ProvisionJob.objects.create(
            tenant=dropped,
            kind=ProvisionJob.Kind.DELETE,
            status=ProvisionJob.Status.SUCCEEDED,
            finished_at=now - timedelta(days=1),
        )

        self._login()
        with mock.patch(
            "control.db.ensure_tenant_connection",
            side_effect=AssertionError("tenant database opened"),
        ):
            with CaptureQueriesContext(connection) as baseline_queries:
                page = self.client.get("/control/")

        self.assertEqual(page.status_code, 200)
        stats = page.context["stats"]
        self.assertEqual(stats["total"], 5)
        self.assertEqual(stats["active"], 2)
        self.assertEqual(stats["provisioning"], 1)
        self.assertEqual(stats["suspended"], 1)
        self.assertEqual(stats["failed_jobs_7d"], 1)
        # stale (older than 7d) + missing + paused (never backed up); dropped is excluded.
        self.assertEqual(stats["backup_stale"], 3)
        self.assertEqual(stats["no_backup"], 2)
        self.assertEqual(stats["old_backup"], 1)

        for idx in range(5):
            extra = self._create_tenant(f"extra{idx}", status=Tenant.Status.ACTIVE)
            ProvisionJob.objects.create(
                tenant=extra,
                kind=ProvisionJob.Kind.BACKUP,
                status=ProvisionJob.Status.SUCCEEDED,
                finished_at=now - timedelta(hours=3),
            )

        with CaptureQueriesContext(connection) as expanded_queries:
            bigger_page = self.client.get("/control/")

        self.assertEqual(bigger_page.status_code, 200)
        self.assertEqual(len(expanded_queries), len(baseline_queries))

    def test_search_miss_keeps_platform_kpis_and_clears_the_table(self):
        self._create_tenant("alpha", status=Tenant.Status.ACTIVE)
        self._create_tenant("bravo", status=Tenant.Status.TRIALING)
        self._create_tenant("paused", status=Tenant.Status.SUSPENDED)
        self._login()

        page = self.client.get("/control/?q=does-not-match")
        self.assertEqual(page.status_code, 200)
        stats = page.context["stats"]
        self.assertEqual(stats["total"], 3)
        self.assertEqual(stats["active"], 1)
        self.assertEqual(stats["trialing"], 1)
        self.assertEqual(stats["suspended"], 1)
        self.assertEqual(page.context["nav_tenant_count"], 3)
        self.assertEqual(page.context["nav_trial_count"], 1)
        self.assertEqual(page.context["rows"], [])
        self.assertTrue(all(tab["count"] == 0 for tab in page.context["status_tabs"]))
        self.assertContains(page, "No tenants match the active filters")
        self.assertContains(page, '<span class="control-nav-count">3</span>', html=True)

        narrowed = self.client.get("/control/?q=alpha")
        self.assertEqual(narrowed.context["stats"]["total"], 3)
        self.assertEqual(narrowed.context["nav_tenant_count"], 3)
        self.assertEqual(
            [row["tenant"].slug for row in narrowed.context["rows"]],
            ["alpha"],
        )
        all_tab = next(tab for tab in narrowed.context["status_tabs"] if tab["id"] == "")
        self.assertEqual(all_tab["count"], 1)

    def test_status_tabs_filter_counts_and_empty_state(self):
        self._create_tenant("alpha", name="Alpha Corp", status=Tenant.Status.ACTIVE)
        self._create_tenant("bravo", name="Bravo Org", status=Tenant.Status.PROVISIONING)
        self._create_tenant("charlie", name="Charlie Ltd", status=Tenant.Status.SUSPENDED)

        self._login()
        all_page = self.client.get("/control/")
        self.assertContains(all_page, "Alpha Corp")
        self.assertContains(all_page, "Bravo Org")
        self.assertContains(all_page, "Charlie Ltd")

        active_page = self.client.get("/control/?status=active")
        self.assertContains(active_page, "Alpha Corp")
        self.assertNotContains(active_page, "Bravo Org")
        self.assertNotContains(active_page, "Charlie Ltd")

        prov_page = self.client.get("/control/?status=provisioning")
        self.assertContains(prov_page, "Bravo Org")
        self.assertNotContains(prov_page, "Alpha Corp")

        susp_page = self.client.get("/control/?status=suspended")
        self.assertContains(susp_page, "Charlie Ltd")
        self.assertNotContains(susp_page, "Alpha Corp")

        failed_page = self.client.get("/control/?status=failed")
        self.assertContains(failed_page, "No tenants match the active filters")

    def test_detail_sections_preserve_fields_and_job_actions(self):
        tenant = self._create_tenant("north", name="Northwind", plan="growth")
        tenant.set_setup_password("setup-once-token")
        tenant.save(update_fields=["setup_password_encrypted"])

        self._login()
        detail = self.client.get("/control/tenants/north/")
        self.assertEqual(detail.status_code, 200)
        self.assertContains(detail, 'id="section-overview"')
        self.assertContains(detail, 'id="section-operations"')
        self.assertContains(detail, 'id="section-access"')
        self.assertContains(detail, "Northwind")
        self.assertContains(detail, "tenant_north")
        self.assertContains(detail, "north.localhost")
        self.assertContains(detail, "Growth")
        self.assertContains(detail, "Pending")
        self.assertNotContains(detail, "setup-once-token")

        only_ops = self.client.get("/control/tenants/north/?section=operations")
        self.assertEqual(only_ops.status_code, 200)
        self.assertEqual(only_ops.context["active_section"], "operations")

        with mock.patch(
            "control.provisioning.maintenance_cursor",
            side_effect=AssertionError("inline SQL during POST"),
        ):
            self.assertEqual(
                self.client.post("/control/tenants/north/backup/").status_code, 302
            )
            self.assertEqual(
                self.client.post("/control/tenants/north/migrate/").status_code, 302
            )
            self.assertEqual(
                self.client.post(
                    "/control/tenants/north/suspend/",
                    {"reason": "Billing review"},
                ).status_code,
                302,
            )

        tenant.status = Tenant.Status.SUSPENDED
        tenant.save(update_fields=["status"])
        self.assertEqual(
            self.client.post("/control/tenants/north/resume/").status_code, 302
        )
        self.assertEqual(
            set(tenant.jobs.values_list("kind", flat=True)),
            {
                ProvisionJob.Kind.BACKUP,
                ProvisionJob.Kind.MIGRATE,
                ProvisionJob.Kind.SUSPEND,
                ProvisionJob.Kind.RESUME,
            },
        )

    def test_rejected_job_enqueue_renders_an_operations_error(self):
        self._create_tenant("north")
        self._login()
        cases = (
            ("control.views.enqueue_backup", "/control/tenants/north/backup/", {}),
            ("control.views.enqueue_migrate", "/control/tenants/north/migrate/", {}),
            (
                "control.views.enqueue_suspend",
                "/control/tenants/north/suspend/",
                {"reason": "Billing review"},
            ),
            ("control.views.enqueue_resume", "/control/tenants/north/resume/", {}),
        )
        for target, path, data in cases:
            with mock.patch(target, side_effect=ProvisionError("queue refused")):
                response = self.client.post(path, data)
            self.assertEqual(response.status_code, 400, path)
            self.assertEqual(response.context["active_section"], "operations")
            self.assertEqual(response.context["action_error"], "queue refused")
            self.assertContains(response, "queue refused", status_code=400)
        self.assertFalse(ProvisionJob.objects.filter(tenant__slug="north").exists())

    def test_danger_zone_stays_available_until_delete_starts(self):
        tenant = self._create_tenant("north")
        self._login()
        visible = (
            Tenant.Status.SUSPENDED,
            Tenant.Status.ACTIVE,
            Tenant.Status.TRIALING,
            Tenant.Status.PAST_DUE,
            Tenant.Status.FAILED,
            Tenant.Status.PROVISIONING,
        )
        for status in visible:
            tenant.status = status
            tenant.save(update_fields=["status"])
            page = self.client.get("/control/tenants/north/?section=operations")
            self.assertContains(page, "Queue restore")
            self.assertContains(page, "Queue delete")
        for status in (Tenant.Status.DELETED, Tenant.Status.DELETING):
            tenant.status = status
            tenant.save(update_fields=["status"])
            page = self.client.get("/control/tenants/north/?section=operations")
            self.assertNotContains(page, "Queue restore")
            self.assertNotContains(page, "Queue delete")

    def test_lapsed_trial_past_due_can_convert(self):
        lapsed = self._create_tenant("lapse", status=Tenant.Status.PAST_DUE, plan="starter")
        lapsed.trial_ends_at = timezone.now() - timedelta(days=1)
        lapsed.save(update_fields=["trial_ends_at"])
        overdue = self._create_tenant("overdue", status=Tenant.Status.PAST_DUE)
        self._login()

        form = self.client.get("/control/tenants/lapse/")
        self.assertContains(form, "Convert to active")
        billed = self.client.get("/control/tenants/overdue/")
        self.assertNotContains(billed, "Convert to active")

        rejected = self.client.post("/control/tenants/overdue/convert/")
        self.assertEqual(rejected.status_code, 400)
        overdue.refresh_from_db()
        self.assertEqual(overdue.status, Tenant.Status.PAST_DUE)
        self.assertFalse(
            OperatorAudit.objects.filter(
                slug="overdue", action=OperatorAudit.Action.TRIAL_CONVERT
            ).exists()
        )

        converted = self.client.post("/control/tenants/lapse/convert/")
        self.assertEqual(converted.status_code, 302)
        lapsed.refresh_from_db()
        self.assertEqual(lapsed.status, Tenant.Status.ACTIVE)
        self.assertIsNone(lapsed.trial_ends_at)
        self.assertTrue(
            OperatorAudit.objects.filter(
                slug="lapse", action=OperatorAudit.Action.TRIAL_CONVERT
            ).exists()
        )
        self.assertEqual(Invoice.objects.filter(tenant=lapsed).count(), 1)
