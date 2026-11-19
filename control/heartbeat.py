"""Provisioner liveness. The worker writes; the dashboard and /ready/ read.

The cache entry lives under the control scope. A missing cache entry falls
back to the single control-database row. A beat older than two minutes is
stale. A page that already has a fresh cache entry does not query.
"""

from datetime import timedelta

from django.core.cache import cache
from django.utils import timezone
from django.utils.dateparse import parse_datetime

from control.models import ProvisionJob, ProvisionerHeartbeat
from horilla.isolation import activate_cache_scope, clear_cache_scope

HEARTBEAT_KEY = "provisioner-heartbeat"
STALE_AFTER = timedelta(minutes=2)
CACHE_TTL = 60 * 60


def beat(now=None) -> None:
    moment = now or timezone.now()
    token = activate_cache_scope("control")
    try:
        cache.set(HEARTBEAT_KEY, moment.isoformat(), timeout=CACHE_TTL)
    finally:
        clear_cache_scope(token)
    ProvisionerHeartbeat.objects.update_or_create(
        pk=1,
        defaults={"beat_at": moment},
    )


def _cached_beat():
    token = activate_cache_scope("control")
    try:
        raw = cache.get(HEARTBEAT_KEY)
    finally:
        clear_cache_scope(token)
    if not raw:
        return None
    parsed = parse_datetime(str(raw))
    if parsed is None:
        return None
    if timezone.is_naive(parsed):
        parsed = timezone.make_aware(parsed)
    return parsed


def heartbeat_status(now=None):
    """``(state, beat_at)`` where state is ok, stale, or missing."""
    moment = now or timezone.now()
    seen = _cached_beat()
    if seen is None:
        row = ProvisionerHeartbeat.objects.filter(pk=1).first()
        seen = row.beat_at if row is not None else None
    if seen is None:
        return "missing", None
    if moment - seen > STALE_AFTER:
        return "stale", seen
    return "ok", seen


def _ago(moment, then) -> str:
    minutes = max(0, int((moment - then).total_seconds()) // 60)
    if minutes < 1:
        return "less than a minute"
    if minutes == 1:
        return "1 minute"
    return f"{minutes} minutes"


def provisioner_notice(now=None) -> str:
    """Banner text, or empty when the provisioner is current.

    A fresh cache entry returns without a query. A stale or missing beat
    adds one query for the oldest queued job.
    """
    moment = now or timezone.now()
    state, seen = heartbeat_status(moment)
    if state == "ok":
        return ""
    oldest = (
        ProvisionJob.objects.filter(status=ProvisionJob.Status.QUEUED)
        .order_by("pk")
        .only("started_at")
        .first()
    )
    if state == "missing":
        text = "The provisioner has not reported yet."
    else:
        text = f"The provisioner last reported {_ago(moment, seen)} ago."
    if oldest is not None:
        if oldest.started_at is not None:
            text += f" Oldest queued job is {_ago(moment, oldest.started_at)} old."
        else:
            text += " Oldest queued job is still waiting."
    return text
