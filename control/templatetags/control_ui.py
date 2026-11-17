from django import template
from django.utils.html import format_html

register = template.Library()

_TENANT_LABELS = {
    "provisioning": "PROVISIONING",
    "active": "ACTIVE",
    "suspended": "SUSPENDED",
    "failed": "FAILED",
    "deleting": "DELETING",
    "deleted": "DELETED",
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


@register.filter
def tenant_status_badge(status: str):
    label = _TENANT_LABELS.get(status, (status or "").upper())
    return _pill(label, _PILL_TONES.get(status, "neutral"))


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
    elif section == "operators":
        if name == "control-operators" or name.startswith("control-operator"):
            return active
    return idle