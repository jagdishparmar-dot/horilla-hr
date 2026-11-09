"""
Per-date flags the mobile Summary calendar needs besides punch rows.

Leave, holidays and company week-offs exist on days with no Attendance row,
so they cannot live on the serializer. Attached as ``day_context`` next to
the paginated ``results`` of ``GET /attendance/my-attendance/``.
"""

from datetime import date, timedelta

from django.apps import apps
from django.db.models import Q


def _as_date(raw):
    if isinstance(raw, date):
        return raw
    try:
        return date.fromisoformat(str(raw).strip())
    except ValueError:
        return None


def build_day_context(employee, start_raw, end_raw):
    start = _as_date(start_raw)
    end = _as_date(end_raw)
    if start is None or end is None:
        return []
    if end < start:
        start, end = end, start

    holiday_dates = set()
    try:
        from base.methods import get_holiday_dates

        holiday_dates = {
            d for d in get_holiday_dates(start, end, employee) if start <= d <= end
        }
    except Exception:
        holiday_dates = set()

    company_leave_dates = set()
    try:
        from base.methods import get_company_leave_dates

        for year in {start.year, end.year}:
            for d in get_company_leave_dates(year):
                if start <= d <= end:
                    company_leave_dates.add(d)
    except Exception:
        company_leave_dates = set()

    leave_by_date = {}
    if apps.is_installed("leave"):
        LeaveRequest = apps.get_model("leave", "LeaveRequest")
        rows = (
            LeaveRequest.objects.filter(
                employee_id=employee,
                status__in=["approved", "cancel_requested"],
                start_date__lte=end,
            )
            .filter(Q(end_date__gte=start) | Q(end_date__isnull=True, start_date__gte=start))
            .select_related("leave_type_id")
        )
        for leave in rows:
            first = leave.start_date
            last = leave.end_date or leave.start_date
            if first is None:
                continue
            leave_type = leave.leave_type_id
            name = getattr(leave_type, "name", None) or "Leave"
            paid = True
            getter = getattr(leave_type, "get_payment_percentage", None)
            if callable(getter):
                try:
                    paid = float(getter() or 0) > 0
                except Exception:
                    paid = getattr(leave_type, "payment", "unpaid") != "unpaid"
            elif leave_type is not None:
                paid = getattr(leave_type, "payment", "unpaid") != "unpaid"
            cursor = max(first, start)
            stop = min(last, end)
            while cursor <= stop:
                leave_by_date[cursor] = {"name": name, "paid": paid}
                cursor += timedelta(days=1)

    days = []
    cursor = start
    while cursor <= end:
        leave = leave_by_date.get(cursor)
        days.append(
            {
                "date": cursor.isoformat(),
                "is_holiday": cursor in holiday_dates,
                "is_company_leave": cursor in company_leave_dates,
                "leave_name": None if leave is None else leave["name"],
                "leave_paid": None if leave is None else leave["paid"],
            }
        )
        cursor += timedelta(days=1)
    return days
