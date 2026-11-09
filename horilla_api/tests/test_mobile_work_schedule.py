"""
Assigned-shift week for the mobile Shift tab.

Home used to invent 09:00–17:00 on days with no EmployeeShiftSchedule row,
so a Friday/Sunday week-off looked like an office day. The Shift tab reads
this payload (and home's embedded work_schedule) and must see null times
plus has_schedule=false on those days.
"""

from datetime import date, time
from unittest.mock import patch

from django.test import TestCase, override_settings
from rest_framework.test import APIClient

from base.models import (
    EmployeeShift,
    EmployeeShiftDay,
    EmployeeShiftSchedule,
    RotatingShift,
    RotatingShiftAssign,
)
from horilla.horilla_middlewares import set_selected_company
from horilla.testkit import make_company, make_employee, make_user

SCHEDULE_URL = "/api/v1/mobile/work-schedule/"
HOME_URL = "/api/v1/mobile/home/"

# Tuesday, so the default Sunday–Saturday week is 8 Mar – 14 Mar 2026.
FIXED_TODAY = date(2026, 3, 10)


def _weekday_hours(shift, start, end, days=("monday", "tuesday", "wednesday", "thursday", "friday")):
    for name in days:
        EmployeeShiftSchedule.objects.create(
            shift_id=shift,
            day=EmployeeShiftDay.objects.get_or_create(day=name)[0],
            start_time=start,
            end_time=end,
            minimum_working_hour="08:00",
        )


class MobileWorkScheduleTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        set_selected_company(None)
        self.company = make_company("Roster Co")
        self.user = make_user("roster_user")
        self.shift = EmployeeShift.objects.create(employee_shift="Morning")
        self.shift.company_id.add(self.company)
        for name in ("monday", "tuesday", "wednesday", "thursday", "friday"):
            EmployeeShiftSchedule.objects.create(
                shift_id=self.shift,
                day=EmployeeShiftDay.objects.get_or_create(day=name)[0],
                start_time=time(9, 30),
                end_time=time(18, 30),
                minimum_working_hour="08:00",
            )
        self.employee = make_employee(
            company=self.company,
            email="roster@test.horilla",
            first_name="Rina",
            user=self.user,
            shift=self.shift,
        )
        self.client.force_authenticate(user=self.user)
        clock = patch(
            "horilla_api.api_views.mobile.views._company_today",
            return_value=FIXED_TODAY,
        )
        clock.start()
        self.addCleanup(clock.stop)

    def test_requires_authentication(self):
        self.assertEqual(APIClient().get(SCHEDULE_URL).status_code, 401)

    def test_rejects_malformed_from_date(self):
        response = self.client.get(SCHEDULE_URL, {"from_date": "10-03-2026"})
        self.assertEqual(response.status_code, 400)

    def test_mon_fri_shift_leaves_weekend_without_invented_hours(self):
        response = self.client.get(SCHEDULE_URL)
        self.assertEqual(response.status_code, 200, response.content)
        data = response.data
        self.assertEqual(data["shift_name"], "Morning")
        self.assertEqual(data["week_start"], "2026-03-08")
        self.assertEqual(data["week_end"], "2026-03-14")
        self.assertEqual(len(data["days"]), 7)

        by_key = {row["day_key"]: row for row in data["days"]}
        tuesday = by_key["tuesday"]
        self.assertTrue(tuesday["has_schedule"])
        self.assertTrue(tuesday["is_today"])
        self.assertEqual(tuesday["start_time"], "09:30")
        self.assertEqual(tuesday["end_time"], "18:30")
        self.assertEqual(tuesday["shift_name"], "Morning")

        for off in ("saturday", "sunday"):
            row = by_key[off]
            self.assertFalse(row["has_schedule"], off)
            self.assertIsNone(row["start_time"], off)
            self.assertIsNone(row["end_time"], off)

    def test_from_and_to_date_select_another_week(self):
        response = self.client.get(
            SCHEDULE_URL,
            {"from_date": "2026-03-15", "to_date": "2026-03-21"},
        )
        self.assertEqual(response.status_code, 200, response.content)
        data = response.data
        self.assertEqual(data["week_start"], "2026-03-15")
        self.assertEqual(data["week_end"], "2026-03-21")
        self.assertEqual([row["date"] for row in data["days"]], [
            "2026-03-15",
            "2026-03-16",
            "2026-03-17",
            "2026-03-18",
            "2026-03-19",
            "2026-03-20",
            "2026-03-21",
        ])
        monday = data["days"][1]
        self.assertEqual(monday["day_key"], "monday")
        self.assertTrue(monday["has_schedule"])
        self.assertEqual(monday["start_time"], "09:30")

    def test_home_work_schedule_uses_the_same_null_off_days(self):
        data = self.client.get(HOME_URL).data["work_schedule"]
        sunday = next(row for row in data["days"] if row["day_key"] == "sunday")
        self.assertFalse(sunday["has_schedule"])
        self.assertIsNone(sunday["start_time"])
        self.assertIsNone(sunday["end_time"])
        self.assertNotEqual(sunday["start_time"], "09:00")
        self.assertEqual(data["today"], "2026-03-10")

    def test_employee_without_a_shift_is_off_every_day(self):
        other_user = make_user("noshift_user")
        make_employee(
            company=self.company,
            email="noshift@test.horilla",
            first_name="NoShift",
            user=other_user,
        )
        client = APIClient()
        client.force_authenticate(user=other_user)
        data = client.get(SCHEDULE_URL).data
        self.assertEqual(data["shift_name"], "General")
        self.assertTrue(all(not row["has_schedule"] for row in data["days"]))
        self.assertTrue(all(row["start_time"] is None for row in data["days"]))

    def test_payload_includes_company_today_and_timezone(self):
        data = self.client.get(SCHEDULE_URL).data
        self.assertEqual(data["today"], "2026-03-10")
        self.assertTrue(data["timezone"])
        self.assertEqual(data["week_start"], "2026-03-08")

    @override_settings(TIME_ZONE="UTC")
    def test_timezone_field_follows_django_time_zone(self):
        data = self.client.get(SCHEDULE_URL).data
        self.assertEqual(data["timezone"], "UTC")
        self.assertEqual(data["today"], "2026-03-10")

    def test_night_shift_keeps_overnight_hours(self):
        night = EmployeeShift.objects.create(employee_shift="Night")
        night.company_id.add(self.company)
        _weekday_hours(night, time(22, 0), time(6, 0))
        self.employee.employee_work_info.shift_id = night
        self.employee.employee_work_info.save()

        data = self.client.get(SCHEDULE_URL).data
        tuesday = next(row for row in data["days"] if row["day_key"] == "tuesday")
        self.assertEqual(tuesday["shift_name"], "Night")
        self.assertEqual(tuesday["start_time"], "22:00")
        self.assertEqual(tuesday["end_time"], "06:00")

    def test_rotating_assignment_changes_shift_mid_range(self):
        """
        Work-info is still Morning (the rotate job has not run). The range
        straddles the first switch, so days before 8 Mar stay Morning and
        days from 8 Mar are Evening — shift1 of the rotation.
        """
        evening = EmployeeShift.objects.create(employee_shift="Evening")
        evening.company_id.add(self.company)
        _weekday_hours(evening, time(14, 0), time(22, 0))
        rotation = RotatingShift.objects.create(
            name="Day/Evening",
            shift1=evening,
            shift2=self.shift,
        )
        RotatingShiftAssign.objects.create(
            employee_id=self.employee,
            rotating_shift_id=rotation,
            start_date=date(2026, 3, 1),
            next_change_date=date(2026, 3, 8),
            current_shift=self.shift,
            next_shift=evening,
            based_on="after",
            rotate_after_day=7,
            additional_data={"next_shift_index": 1},
        )

        data = self.client.get(
            SCHEDULE_URL,
            {"from_date": "2026-03-02", "to_date": "2026-03-14"},
        ).data
        by_date = {row["date"]: row for row in data["days"]}

        friday = by_date["2026-03-06"]
        self.assertEqual(friday["shift_name"], "Morning")
        self.assertEqual(friday["start_time"], "09:30")

        sunday = by_date["2026-03-08"]
        self.assertEqual(sunday["shift_name"], "Evening")
        self.assertFalse(sunday["has_schedule"])
        self.assertIsNone(sunday["start_time"])

        tuesday = by_date["2026-03-10"]
        self.assertEqual(tuesday["shift_name"], "Evening")
        self.assertEqual(tuesday["start_time"], "14:00")
        self.assertEqual(tuesday["end_time"], "22:00")

        future = self.client.get(
            SCHEDULE_URL,
            {"from_date": "2026-03-16", "to_date": "2026-03-16"},
        ).data["days"][0]
        self.assertEqual(future["shift_name"], "Morning")
        self.assertEqual(future["start_time"], "09:30")
