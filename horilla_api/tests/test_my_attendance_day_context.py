"""day_context on GET /attendance/my-attendance/ for the mobile Summary tab."""

from datetime import date, timedelta

from django.test import TestCase
from rest_framework.test import APIClient

from horilla.horilla_middlewares import set_selected_company
from horilla.testkit import make_company, make_employee, make_user

URL = "/api/v1/attendance/my-attendance/"
DAY = date(2026, 3, 10)


class MyAttendanceDayContextTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        set_selected_company(None)
        self.company = make_company("Context Co")
        self.user = make_user("ctx_user")
        self.employee = make_employee(
            company=self.company,
            email="ctx@test.horilla",
            first_name="Cora",
            user=self.user,
        )
        self.client.force_authenticate(user=self.user)

    def test_range_includes_one_flag_per_date(self):
        start = DAY
        end = DAY + timedelta(days=6)
        response = self.client.get(
            URL,
            {"from_date": start.isoformat(), "to_date": end.isoformat(), "page_size": 31},
        )
        self.assertEqual(response.status_code, 200, response.content)
        context = response.data.get("day_context")
        self.assertIsInstance(context, list)
        self.assertEqual(len(context), 7)
        self.assertEqual(context[0]["date"], start.isoformat())
        self.assertEqual(context[-1]["date"], end.isoformat())
        for row in context:
            self.assertIn("is_holiday", row)
            self.assertIn("is_company_leave", row)
            self.assertIn("leave_name", row)
            self.assertIn("leave_paid", row)
