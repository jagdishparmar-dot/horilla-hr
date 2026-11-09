"""Work-site geofence overrides the company fence for assigned employees."""

from django.test import RequestFactory, TestCase

from geofencing.models import WorkSite, enforceable_fence
from horilla.testkit import make_company, make_employee, make_user


class WorkSiteFenceTests(TestCase):
    def setUp(self):
        self.company = make_company("Acme")
        self.user = make_user("site-employee")
        self.employee = make_employee(
            company=self.company,
            email="site-employee@test.horilla",
            user=self.user,
        )
        self.mumbai = WorkSite.objects.create(
            company_id=self.company,
            name="Mumbai",
            latitude=19.076,
            longitude=72.8777,
            radius_in_meters=150,
            start=True,
        )
        self.employee.employee_work_info.work_site = self.mumbai
        self.employee.employee_work_info.save()
        self.employee = type(self.employee).objects.select_related(
            "employee_work_info__work_site"
        ).get(pk=self.employee.pk)

    def test_an_enabled_site_is_the_fence(self):
        self.assertEqual(enforceable_fence(self.employee), self.mumbai)

    def test_a_disabled_site_does_not_fall_back_to_the_company_fence(self):
        from geofencing.models import GeoFencing

        GeoFencing.objects.bulk_create(
            [
                GeoFencing(
                    latitude=19.076,
                    longitude=72.8777,
                    radius_in_meters=5000,
                    company_id=self.company,
                    start=True,
                )
            ]
        )
        self.mumbai.start = False
        self.mumbai.save()
        self.employee.employee_work_info.refresh_from_db()
        self.assertIsNone(enforceable_fence(self.employee))

    def test_web_punch_outside_the_assigned_site_is_refused(self):
        from attendance.methods.utils import geofence_denial_web

        request = RequestFactory().get("/", {"latitude": "12.97", "longitude": "77.59"})
        request.user = self.user
        self.assertIsNotNone(geofence_denial_web(request, self.company))

    def test_web_punch_inside_the_assigned_site_is_allowed(self):
        from attendance.methods.utils import geofence_denial_web

        request = RequestFactory().get("/", {"latitude": "19.076", "longitude": "72.8777"})
        request.user = self.user
        self.assertIsNone(geofence_denial_web(request, self.company))

    def test_mobile_config_reports_the_assigned_site(self):
        from horilla_api.api_views.mobile.views import _geofence_block

        block = _geofence_block(self.employee)
        self.assertTrue(block["enabled"])
        self.assertEqual(block["latitude"], self.mumbai.latitude)
        self.assertEqual(block["radius_in_meters"], 150)
