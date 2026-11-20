from django import template
from django.utils.html import format_html

from control.catalog import format_inr

register = template.Library()

_TENANT_LABELS = {
    "provisioning": "Provisioning",
    "active": "Active",
    "trialing": "Trialing",
    "past_due": "Past due",
    "suspended": "Suspended",
    "failed": "Failed",
    "deleting": "Deleting",
    "deleted": "Deleted",
}

_JOB_LABELS = {
    "queued": "QUEUED",
    "running": "RUNNING",
    "succeeded": "SUCCEEDED",
    "failed": "FAILED",
}


_PILL_TONES = {
    "provisioning": "warn",
    "active": "ok",
    "trialing": "warn",
    "past_due": "danger",
    "suspended": "neutral",
    "failed": "danger",
    "deleting": "warn",
    "deleted": "neutral",
    "queued": "info",
    "running": "warn",
    "succeeded": "ok",
}


def _pill(label: str, tone: str) -> str:
    return format_html(
        '<span class="control-pill control-pill-{}">{}</span>',
        tone,
        label,
    )


_STATUS_CLASS = {
    "ok": "control-status control-status-ok",
    "warn": "control-status control-status-warn",
    "danger": "control-status control-status-danger",
    "info": "control-status control-status-info",
    "neutral": "control-status control-status-neutral",
}


@register.filter
def tenant_status_badge(status: str):
    label = _TENANT_LABELS.get(status, (status or "").replace("_", " ").title())
    tone = _PILL_TONES.get(status, "neutral")
    return format_html(
        '<span class="{}">{}</span>',
        _STATUS_CLASS.get(tone, _STATUS_CLASS["neutral"]),
        label,
    )


@register.filter
def job_status_badge(status: str):
    label = _JOB_LABELS.get(status, (status or "").upper())
    return _pill(label, _PILL_TONES.get(status, "neutral"))


@register.filter
def yesno_badge(value: bool):
    if value:
        return _pill("YES", "ok")
    return _pill("NO", "neutral")


@register.filter
def inr(value) -> str:
    return format_inr(value)


@register.filter
def initials(value: str) -> str:
    parts = [part for part in (value or "").replace("-", " ").split() if part]
    if not parts:
        return "?"
    if len(parts) == 1:
        return parts[0][:2].upper()
    return (parts[0][0] + parts[1][0]).upper()


@register.filter
def avatar_hue(value: str) -> int:
    total = sum(ord(char) for char in (value or "tenant"))
    return (total * 47) % 360


@register.simple_tag
def control_nav_active(request, section: str) -> str:
    name = ""
    if request.resolver_match:
        name = request.resolver_match.url_name or ""
    active = "control-nav-link control-nav-link-active"
    idle = "control-nav-link"
    if section == "tenants":
        if name == "control-home" or name.startswith("control-tenant"):
            return active
    elif section == "plans":
        if name == "control-plans" or name.startswith("control-plan"):
            return active
    elif section == "requests":
        if name == "control-requests" or name.startswith("control-request"):
            return active
    elif section == "billing":
        if name == "control-billing" or name.startswith("control-billing"):
            return active
    elif section == "audit":
        if name == "control-audit" or name.startswith("control-audit"):
            return active
    elif section == "operators":
        if name == "control-operators" or name.startswith("control-operator"):
            return active
    return idle