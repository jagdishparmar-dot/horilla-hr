"""
The shift that applied (or will apply) on a calendar date.

``employee.get_shift()`` is whatever is on work-info *right now*. After a
rotating assignment starts, that is only correct between switches. The mobile
Shift tab needs the shift for each date in the requested range, including
dates the nightly ``rotate_shift`` job has not reached yet.

Walk matches ``RotatingShiftAssignForm.save`` (initial next_shift = shift1,
next_change on start + interval) and ``update_rotating_shift_assign``
(on the switch date, current becomes the previous next).
"""

from __future__ import annotations

import calendar
from datetime import date, timedelta

from django.conf import settings
from django.utils import timezone


_DAY_INDEX = {
    "monday": 0,
    "tuesday": 1,
    "wednesday": 2,
    "thursday": 3,
    "friday": 4,
    "saturday": 5,
    "sunday": 6,
}

_WALK_GUARD = 400
_UNSET = object()


def company_today():
    """Company calendar date — Django TIME_ZONE, not the phone and not UTC date.today()."""
    return timezone.localdate()


def company_timezone_name():
    return str(getattr(settings, "TIME_ZONE", None) or "UTC")


def load_rotating_assigns(employee):
    from base.models import RotatingShiftAssign

    return list(
        RotatingShiftAssign.objects.filter(employee_id=employee, is_active=True)
        .select_related(
            "rotating_shift_id",
            "rotating_shift_id__shift1",
            "rotating_shift_id__shift2",
            "current_shift",
            "next_shift",
        )
        .order_by("-start_date")
    )


def work_info_shift(employee):
    """
    Shift on ``employee_work_info``, loaded from the database.

    ``employee.get_shift()`` reads the in-memory related object. Factories and
    bulk ``QuerySet.update`` change the row without touching that cache, and
    ``APIClient.force_authenticate`` reuses the same User, so the reverse
    ``employee_get`` can still hold a work-info with ``shift_id=None``.
    """
    from employee.models import EmployeeWorkInformation

    work = (
        EmployeeWorkInformation.objects.select_related("shift_id")
        .filter(employee_id=employee)
        .first()
    )
    return None if work is None else work.shift_id


def shift_on_date(employee, on_date, assigns=None, static_shift=_UNSET):
    """
    Shift in force on ``on_date``.

    No rotating assign covering the date → work-info shift. Otherwise reconstruct
    the rotation so a week that straddles a switch is not stamped with today's
    shift on every day.
    """
    static = (
        work_info_shift(employee) if static_shift is _UNSET else static_shift
    )
    assign = _assign_covering(on_date, assigns if assigns is not None else load_rotating_assigns(employee))
    if assign is None:
        return static
    planned = _planned_shift(assign, on_date)
    return planned if planned is not None else static


def _assign_covering(on_date, assigns):
    for assign in assigns:
        start = getattr(assign, "start_date", None)
        if start is not None and start <= on_date:
            return assign
    return None


def _cycle(assign):
    rotation = getattr(assign, "rotating_shift_id", None)
    if rotation is None:
        return []
    return list(rotation.total_shifts() or [])


def _planned_shift(assign, on_date):
    start = assign.start_date
    if start is not None and on_date < start:
        return None
    nxt = assign.next_change_date
    if nxt is not None and on_date >= nxt:
        return _walk_forward(assign, on_date)
    period_start = _live_period_start(assign)
    if period_start is not None and on_date >= period_start:
        return assign.current_shift
    return _simulate_from_start(assign, on_date)


def _walk_forward(assign, on_date):
    """Apply switches the nightly job has not necessarily run yet."""
    current = assign.current_shift
    nxt = assign.next_shift
    cycle = _cycle(assign)
    data = assign.additional_data or {}
    idx = data.get("next_shift_index")
    if not isinstance(idx, int):
        idx = 1 if cycle else 0
    change = assign.next_change_date
    guard = 0
    while change is not None and on_date >= change and guard < _WALK_GUARD:
        current = nxt
        if cycle:
            idx = idx % len(cycle)
            nxt = cycle[idx]
            idx = (idx + 1) % len(cycle)
        change = _next_change_after(assign, change)
        guard += 1
    return current


def _simulate_from_start(assign, on_date):
    """Historical dates before the live current-shift window."""
    first = _first_change_date(assign)
    if first is None or on_date < first:
        return assign.current_shift
    cycle = [shift for shift in _cycle(assign) if shift is not None]
    if not cycle:
        return assign.current_shift
    switches = 0
    cursor = first
    guard = 0
    while cursor <= on_date and guard < _WALK_GUARD:
        switches += 1
        cursor = _next_change_after(assign, cursor)
        guard += 1
    return cycle[(switches - 1) % len(cycle)]


def _live_period_start(assign):
    nxt = assign.next_change_date
    if nxt is None:
        return assign.start_date
    prev = _step_back(assign, nxt)
    if prev is None:
        return assign.start_date
    start = assign.start_date
    if start is not None and prev < start:
        return start
    return prev


def _first_change_date(assign):
    start = assign.start_date
    if start is None:
        return None
    based = assign.based_on
    if based == "after":
        return start + timedelta(days=int(assign.rotate_after_day or 7))
    if based == "weekly":
        name = (assign.rotate_every_weekend or "monday").lower()
        return _next_week_date(_DAY_INDEX.get(name, 0), start)
    if based == "monthly":
        return _next_monthly_date(start, assign.rotate_every or "1")
    return start + timedelta(days=7)


def _next_change_after(assign, previous):
    based = assign.based_on
    if based == "after":
        return previous + timedelta(days=int(assign.rotate_after_day or 7))
    if based == "weekly":
        return previous + timedelta(days=7)
    if based == "monthly":
        return _next_monthly_date(previous + timedelta(days=1), assign.rotate_every or "1")
    return previous + timedelta(days=7)


def _step_back(assign, change):
    based = assign.based_on
    if based == "after":
        return change - timedelta(days=int(assign.rotate_after_day or 7))
    if based == "weekly":
        return change - timedelta(days=7)
    if based == "monthly":
        return _previous_monthly_date(change, assign.rotate_every or "1")
    return change - timedelta(days=7)


def _next_week_date(target_day, start_date):
    if start_date.weekday() == target_day:
        return start_date
    days_until = (target_day - start_date.weekday()) % 7
    if days_until == 0:
        days_until = 7
    return start_date + timedelta(days=days_until)


def _next_monthly_date(start_date, rotate_every):
    if rotate_every == "last":
        rotate_every = str(calendar.monthrange(start_date.year, start_date.month)[1])
    rotate_every = int(rotate_every)
    if start_date.day <= rotate_every or rotate_every == 0:
        try:
            return date(start_date.year, start_date.month, rotate_every)
        except ValueError:
            nxt = date(start_date.year, start_date.month + 1, 1)
            return date(nxt.year, nxt.month, rotate_every)
    last_day = calendar.monthrange(start_date.year, start_date.month)[1]
    next_month_start = start_date.replace(day=last_day) + timedelta(days=1)
    try:
        return next_month_start.replace(day=rotate_every)
    except ValueError:
        return (
            next_month_start.replace(month=next_month_start.month + 1) + timedelta(days=1)
        ).replace(day=rotate_every)


def _previous_monthly_date(change, rotate_every):
    if rotate_every == "last":
        return date(change.year, change.month, 1) - timedelta(days=1)
    day = int(rotate_every or 1)
    year, month = change.year, change.month - 1
    if month < 1:
        month = 12
        year -= 1
    last = calendar.monthrange(year, month)[1]
    if day == 0:
        day = last
    return date(year, month, min(day, last))
