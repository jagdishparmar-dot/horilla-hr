"""Billable employees for a calendar month, from the stored daily readings.

The rule is the highest daily count in the month. Archiving people on the last
day therefore does not lower the bill, and someone who joined on the 3rd is
counted for the month. Administrators count like any other active employee.
There is no minimum: a tenant is billed for the people counted, not for its
seat limit. Nothing here issues an invoice.
"""

import calendar
from dataclasses import dataclass
from datetime import date

from django.db.models import Max

from control.models import TenantUsageDay

BILLING_RULE = "peak"


@dataclass(frozen=True)
class MonthUsage:
    year: int
    month: int
    billable: int
    readings: int
    days_in_month: int
    first_day: date
    last_day: date
    latest: int

    @property
    def is_complete(self) -> bool:
        """True when every day of the month has a reading."""
        return self.readings >= self.days_in_month


def month_usage(tenant, year: int, month: int) -> MonthUsage | None:
    """Billable employees for one month, or None when nothing was recorded."""
    days_in_month = calendar.monthrange(year, month)[1]
    first = date(year, month, 1)
    last = date(year, month, days_in_month)
    rows = TenantUsageDay.objects.filter(tenant=tenant, day__gte=first, day__lte=last)
    peak = rows.aggregate(peak=Max("active_employees"))["peak"]
    if peak is None:
        return None
    ordered = rows.order_by("day")
    return MonthUsage(
        year=year,
        month=month,
        billable=int(peak),
        readings=rows.count(),
        days_in_month=days_in_month,
        first_day=ordered.first().day,
        last_day=ordered.last().day,
        latest=int(ordered.last().active_employees),
    )
