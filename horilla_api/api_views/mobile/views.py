"""
Screen-shaped aggregates for the mobile client.

Everything else in this API is resource-shaped, and rightly so. The home
screen is the exception: it renders punch state, today's hours, a role band,
who is on leave, the latest announcement and an unread badge, which came to
eight or more round trips on a cold start over a mobile network. The previous
Flutter app made fourteen.

Deliberately narrow. This returns exactly what the home screen draws and
nothing else -- it is a view of existing data, not a second API. Resist
growing it into a general-purpose "give me everything" endpoint; if another
screen needs an aggregate, it gets its own, so each one stays readable and
cheap.
"""

from datetime import date, datetime, timedelta

from django.apps import apps
from django.db.models import F
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from attendance.models import Attendance, AttendanceActivity
from horilla_api.api_methods.base.announcements import announcements_for
from horilla_api.api_methods.base.capabilities import build_capabilities

_WEEKDAY_KEYS = (
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
)


def _format_seconds(seconds):
    seconds = max(int(seconds or 0), 0)
    return f"{seconds // 3600:02}:{(seconds % 3600) // 60:02}:{seconds % 60:02}"


def _working_activities(employee):
    """
    Punches for the attendance day the employee is on right now.

    A night shift that started yesterday still has that attendance date after
    midnight. If that day has an open punch, it is the working day — otherwise
    the button would offer Check-in while the punch API still says they are in.
    A finished yesterday is not shown once today has started.
    """
    today = date.today()
    yesterday = today - timedelta(days=1)
    rows = list(
        AttendanceActivity.objects.filter(
            employee_id=employee,
            attendance_date__gte=yesterday,
            attendance_date__lte=today,
        ).order_by("clock_in_date", "clock_in", "id")
    )
    open_row = next((row for row in reversed(rows) if not row.clock_out), None)
    day = open_row.attendance_date if open_row is not None else today
    return [row for row in rows if row.attendance_date == day]


def _moment(day, moment):
    """
    Rebuild a datetime from the date+time pair rather than reading the
    nullable DateTimeField beside it.

    AttendanceActivity carries two parallel representations: clock_in_date +
    clock_in (always written) and in_datetime (nullable, written by a
    different path), and the same on the way out. A row can therefore carry a
    clock_out with no out_datetime, which is what demo and imported data look
    like. attendance.methods.utils.activity_datetime rebuilds from the pairs
    for this reason; it is not reused here because it insists on both ends of
    an activity and the last one of a day is usually still open.
    """
    return datetime.combine(day, moment) if day and moment else None


def _break_seconds(activities):
    """
    Time between clocking out and clocking back in again today.

    Not a stored field -- Attendance records at_work_second and
    overtime_second but no break total -- so it is derived from the gaps
    between consecutive activity pairs. Computed here rather than in the
    client so every caller agrees on the number.
    """
    total = 0
    for previous, nxt in zip(activities, activities[1:]):
        left = _moment(previous.clock_out_date, previous.clock_out)
        right = _moment(nxt.clock_in_date, nxt.clock_in)
        if left and right:
            gap = (right - left).total_seconds()
            if gap > 0:
                total += gap
    return int(total)


def _hhmm(value):
    return value.strftime("%H:%M") if value else None


def _punch_block(employee, activities):
    open_activity = next((a for a in activities if not a.clock_out), None)
    first = activities[0] if activities else None
    last_out = next((a for a in reversed(activities) if a.clock_out), None)
    started = (
        _moment(open_activity.clock_in_date, open_activity.clock_in)
        if open_activity
        else None
    )
    return {
        "is_clocked_in": open_activity is not None,
        "clock_in_time": _hhmm(first.clock_in) if first else None,
        "clock_out_time": _hhmm(last_out.clock_out) if last_out else None,
        "last_activity_at": started.isoformat() if started else None,
        "activities": [
            {
                "id": activity.id,
                "clock_in": _hhmm(activity.clock_in),
                "clock_out": _hhmm(activity.clock_out),
                "open": activity.clock_out is None,
            }
            for activity in activities
        ],
    }


def _format_hhmm(value):
    if value is None:
        return None
    if hasattr(value, "strftime"):
        return value.strftime("%H:%M")
    return str(value)[:5]


def _infer_request_kind(name):
    text = (name or "").lower()
    if "remote" in text:
        return "remote"
    if "permission" in text:
        return "permission"
    if "casual" in text:
        return "casual"
    if "annual" in text or "vacation" in text or "paid" in text:
        return "annual"
    if "early" in text:
        return "early"
    return "other"


def _work_info_label(employee, attr, nested):
    work = getattr(employee, "employee_work_info", None)
    obj = getattr(work, attr, None) if work else None
    return getattr(obj, nested, None) if obj else None


def _colleague_card(employee):
    return {
        "id": employee.id,
        "name": employee.get_full_name(),
        "avatar": employee.get_avatar(),
        "job_position": _work_info_label(
            employee, "job_position_id", "job_position"
        ),
        "department": _work_info_label(employee, "department_id", "department"),
    }


def _company_employees(employee):
    from employee.models import Employee

    company = employee.get_company()
    qs = Employee.objects.filter(is_active=True).select_related(
        "employee_work_info__job_position_id",
        "employee_work_info__department_id",
        "employee_work_info__company_id",
    )
    if company is not None:
        qs = qs.filter(employee_work_info__company_id=company)
    return qs


def _work_schedule(employee):
    """
    Current week (Sun–Sat) plus day rows from the employee's assigned shift.
    """
    today = date.today()
    # Sunday-start week to match the home schedule card.
    days_since_sunday = (today.weekday() + 1) % 7
    week_start = today - timedelta(days=days_since_sunday)
    week_end = week_start + timedelta(days=6)

    shift = employee.get_shift()
    shift_name = getattr(shift, "employee_shift", None) or "General"
    schedule_by_day = {}
    if shift is not None:
        from base.models import EmployeeShiftSchedule

        for row in EmployeeShiftSchedule.objects.filter(shift_id=shift).select_related(
            "day"
        ):
            key = (row.day.day or "").lower()
            schedule_by_day[key] = row

    days = []
    for offset in range(7):
        day = week_start + timedelta(days=offset)
        key = _WEEKDAY_KEYS[day.weekday()]
        row = schedule_by_day.get(key)
        days.append(
            {
                "date": day.isoformat(),
                "day_key": key,
                "shift_name": (
                    getattr(getattr(row, "shift_id", None), "employee_shift", None)
                    or shift_name
                ),
                "start_time": _format_hhmm(getattr(row, "start_time", None)) or "09:00",
                "end_time": _format_hhmm(getattr(row, "end_time", None)) or "17:00",
                "is_today": day == today,
                "has_schedule": row is not None,
            }
        )

    return {
        "shift_name": shift_name,
        "week_start": week_start.isoformat(),
        "week_end": week_end.isoformat(),
        "days": days,
    }


def _recent_requests(employee, limit=5):
    if not apps.is_installed("leave"):
        return []
    LeaveRequest = apps.get_model("leave", "LeaveRequest")
    rows = (
        LeaveRequest.objects.filter(employee_id=employee)
        .select_related("leave_type_id")
        .order_by("-id")[:limit]
    )
    payload = []
    for leave in rows:
        leave_name = getattr(leave.leave_type_id, "name", None) or "Leave"
        payload.append(
            {
                "id": leave.id,
                "title": leave_name,
                "status": leave.status,
                "requested_days": leave.requested_days,
                "start_date": leave.start_date.isoformat() if leave.start_date else None,
                "end_date": leave.end_date.isoformat() if leave.end_date else None,
                "kind": _infer_request_kind(leave_name),
                "reason": leave.description,
            }
        )
    return payload


def _upcoming_birthdays(employee, limit=5):
    """Same-month upcoming birthdays in the caller's company (dashboard logic)."""
    today = date.today()
    import calendar

    last_day = calendar.monthrange(today.year, today.month)[1]
    rows = (
        _company_employees(employee)
        .filter(
            dob__isnull=False,
            dob__month=today.month,
            dob__day__gte=today.day,
            dob__day__lte=last_day,
        )
        .order_by(F("dob__day").asc(nulls_last=True))[:limit]
    )
    return [_colleague_card(row) for row in rows]


def _new_hires(employee, limit=5, within_days=30):
    today = date.today()
    since = today - timedelta(days=within_days)
    rows = (
        _company_employees(employee)
        .filter(
            employee_work_info__date_joining__isnull=False,
            employee_work_info__date_joining__gte=since,
            employee_work_info__date_joining__lte=today,
        )
        .exclude(id=employee.id)
        .order_by("-employee_work_info__date_joining")[:limit]
    )
    return [_colleague_card(row) for row in rows]


def _geofence_block(employee):
    """Config only. The client sends coordinates and the punch endpoint rules."""
    from geofencing.models import enforceable_fence, fence_label

    # Assigned work site when its fence is on, otherwise the company/global fence.
    fence = enforceable_fence(employee)
    if fence is None:
        return {"enabled": False}
    return {
        "enabled": True,
        "name": fence_label(fence),
        "latitude": fence.latitude,
        "longitude": fence.longitude,
        "radius_in_meters": fence.radius_in_meters,
    }


def _on_leave_today(employee):
    if not apps.is_installed("leave"):
        return []
    LeaveRequest = apps.get_model("leave", "LeaveRequest")
    today = date.today()
    requests = (
        LeaveRequest.objects.filter(
            status__in=["approved", "cancel_requested"],
            start_date__lte=today,
            end_date__gte=today,
        )
        .select_related("employee_id")
        .exclude(employee_id=employee)[:10]
    )
    return [
        {
            "id": leave.employee_id.id,
            "name": leave.employee_id.get_full_name(),
            "leave_type": getattr(leave.leave_type_id, "leave_type", None),
        }
        for leave in requests
        if leave.employee_id
    ]


def _latest_announcement(employee):
    """
    The newest announcement this employee is actually an audience for.

    Announcements carry targeting (``employees``, ``department``,
    ``job_position``, or the denormalised ``filtered_employees``) and an
    ``expire_date``. Taking ``objects.order_by("-created_at").first()`` ignores
    both, so the home screen served a department-targeted or long-expired
    announcement to everyone in the company. The manager scopes by company, so
    this was never cross-tenant -- but "everyone in the company" is not the
    audience the author chose.
    """
    announcement = announcements_for(employee).order_by("-created_at").first()
    if not announcement:
        return None
    return {
        "id": announcement.id,
        "title": announcement.title,
        "description": announcement.description,
        "created_at": (
            announcement.created_at.isoformat() if announcement.created_at else None
        ),
        "expire_date": (
            announcement.expire_date.isoformat() if announcement.expire_date else None
        ),
    }


def _unread_notification_count(user):
    return user.notifications.unread().count()


def _pending_approvals(request):
    """
    What is waiting on this caller to decide, by kind.

    Built from the same scoping the list endpoints use, so the count matches
    what a client sees when it opens those lists. The caller's own requests
    are excluded: every list includes them, and no one approves their own.
    Kinds with no manager path (reimbursements need the payroll permission)
    count only for callers who could act on them.
    """
    from base.methods import filtersubordinates
    from base.models import ShiftRequest, WorkTypeRequest
    from horilla_api.api_methods.base.methods import permission_based_queryset

    employee = request.user.employee_get
    by_kind = {}

    if apps.is_installed("leave"):
        from leave.methods import filter_conditional_leave_request

        LeaveRequest = apps.get_model("leave", "LeaveRequest")
        LeaveAllocationRequest = apps.get_model("leave", "LeaveAllocationRequest")
        leave = filtersubordinates(
            request, LeaveRequest.objects.all(), "leave.view_leaverequest"
        ) | filter_conditional_leave_request(request)
        by_kind["leave"] = (
            leave.filter(status="requested")
            .exclude(employee_id=employee)
            .distinct()
            .count()
        )
        by_kind["allocation"] = (
            filtersubordinates(
                request,
                LeaveAllocationRequest.objects.all(),
                "leave.view_leaveallocationrequest",
            )
            .filter(status="requested")
            .exclude(employee_id=employee)
            .count()
        )

    by_kind["attendance"] = (
        filtersubordinates(
            request=request,
            perm="attendance.view_attendance",
            queryset=Attendance.objects.filter(is_validate_request=True),
        )
        .exclude(employee_id=employee)
        .count()
    )

    for kind, model, perm in (
        ("shift", ShiftRequest, "base.view_shiftrequest"),
        ("work_type", WorkTypeRequest, "base.view_worktyperequest"),
    ):
        by_kind[kind] = (
            permission_based_queryset(
                request.user, perm, model.objects.all(), user_obj=True
            )
            .filter(approved=False, canceled=False)
            .exclude(employee_id=employee)
            .count()
        )

    if apps.is_installed("payroll") and request.user.has_perm(
        "payroll.change_reimbursement"
    ):
        Reimbursement = apps.get_model("payroll", "Reimbursement")
        by_kind["reimbursement"] = (
            Reimbursement.objects.filter(status="requested")
            .exclude(employee_id=employee)
            .count()
        )

    return {"total": sum(by_kind.values()), "by_kind": by_kind}


class MobileHomeAPIView(APIView):
    """Everything the home screen draws, in one request."""

    permission_classes = [IsAuthenticated]

    def get(self, request):
        employee = request.user.employee_get
        activities = _working_activities(employee)
        working_day = (
            activities[0].attendance_date if activities else date.today()
        )
        attendance_today = Attendance.objects.filter(
            employee_id=employee, attendance_date=working_day
        ).first()
        worked_seconds = (
            int(attendance_today.get_at_work_from_activities())
            if attendance_today is not None
            else 0
        )

        return Response(
            {
                "employee": {
                    "id": employee.id,
                    "name": employee.get_full_name(),
                    "avatar": employee.get_avatar(),
                    "badge_id": employee.badge_id,
                    "email": employee.email,
                    "phone": employee.phone,
                    "job_position": getattr(
                        getattr(
                            getattr(employee, "employee_work_info", None),
                            "job_position_id",
                            None,
                        ),
                        "job_position",
                        None,
                    ),
                    "department": getattr(
                        getattr(
                            getattr(employee, "employee_work_info", None),
                            "department_id",
                            None,
                        ),
                        "department",
                        None,
                    ),
                    "shift_id": getattr(employee.get_shift(), "id", None),
                    "work_type_id": getattr(
                        getattr(
                            getattr(employee, "employee_work_info", None),
                            "work_type_id",
                            None,
                        ),
                        "id",
                        None,
                    ),
                },
                "capabilities": build_capabilities(request.user),
                "punch": _punch_block(employee, activities),
                "geofence": _geofence_block(employee),
                "today": {
                    "worked": _format_seconds(worked_seconds),
                    "break": _format_seconds(_break_seconds(activities)),
                    "overtime": _format_seconds(
                        attendance_today.overtime_second if attendance_today else 0
                    ),
                },
                "on_leave_today": _on_leave_today(employee),
                "announcement": _latest_announcement(employee),
                "unread_notifications": _unread_notification_count(request.user),
                "pending_approvals": _pending_approvals(request),
                "work_schedule": _work_schedule(employee),
                "recent_requests": _recent_requests(employee),
                "birthdays": _upcoming_birthdays(employee),
                "new_hires": _new_hires(employee),
            },
            status=200,
        )


class MobileWorkSiteAPIView(APIView):
    """
    Where the signed-in employee is expected to work.

    ``MobileHomeAPIView`` only carries a ``geofence`` block while a fence is
    being *enforced*, which loses the site name the moment an admin switches the
    fence off. This always answers "which site am I assigned to", and whether a
    punch is checked against it.

    ``kind`` is ``site`` (assigned work site), ``company`` (the company / global
    fence, when no site is assigned) or ``null`` (nothing configured).
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from geofencing.models import GeoFencing, fence_label

        employee = request.user.employee_get
        try:
            work_info = employee.employee_work_info
        except Exception:
            work_info = None

        site = getattr(work_info, "work_site", None)
        if site is not None and site.is_active:
            return Response(
                {
                    "kind": "site",
                    "name": fence_label(site),
                    "company": getattr(site.company_id, "company", None),
                    "latitude": site.latitude,
                    "longitude": site.longitude,
                    "radius_in_meters": site.radius_in_meters,
                    "geofence_enabled": bool(site.start),
                    "location": getattr(work_info, "location", None) or None,
                }
            )

        company = employee.get_company()
        fence = GeoFencing.for_company(company) if company is not None else None
        if fence is not None:
            return Response(
                {
                    "kind": "company",
                    "name": fence_label(fence),
                    "company": getattr(company, "company", None),
                    "latitude": fence.latitude,
                    "longitude": fence.longitude,
                    "radius_in_meters": fence.radius_in_meters,
                    "geofence_enabled": bool(fence.start),
                    "location": getattr(work_info, "location", None) or None,
                }
            )
        return Response({"kind": None})
