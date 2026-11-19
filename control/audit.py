"""Dashboard audit rows. Callers must not pass passwords or ciphertext."""

import re

from control.crypto import redact_job_error
from control.models import OperatorAudit

# Frozen for rows written after C5. The data migration uses the same map.
ACTION_CATEGORIES = {
    OperatorAudit.Action.CREATE: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.SUSPEND: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.RESUME: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.BACKUP: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.RESTORE: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.MIGRATE: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.DELETE: OperatorAudit.Category.PROVISIONING,
    OperatorAudit.Action.QUOTA_UPDATE: OperatorAudit.Category.QUOTA,
    OperatorAudit.Action.MODULE_UPDATE: OperatorAudit.Category.QUOTA,
    OperatorAudit.Action.TRIAL_CONVERT: OperatorAudit.Category.SUBSCRIPTION,
    OperatorAudit.Action.INVOICE_ISSUE: OperatorAudit.Category.BILLING,
    OperatorAudit.Action.INVOICE_VOID: OperatorAudit.Category.BILLING,
    OperatorAudit.Action.INVOICE_PAID: OperatorAudit.Category.BILLING,
    OperatorAudit.Action.INVOICE_PAST_DUE: OperatorAudit.Category.BILLING,
    OperatorAudit.Action.CATALOG_UPDATE: OperatorAudit.Category.BILLING,
    OperatorAudit.Action.OPERATOR_CREATE: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.OPERATOR_DEACTIVATE: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.OPERATOR_REACTIVATE: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.OPERATOR_LOGIN: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.OPERATOR_LOGIN_FAILED: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.OPERATOR_PASSWORD_CHANGE: OperatorAudit.Category.SECURITY,
    OperatorAudit.Action.SETUP_PASSWORD_RESET: OperatorAudit.Category.SECURITY,
}

_HIDDEN_DETAIL = re.compile(
    r"(?i)setup_password\S*|db_password\S*|postgres(?:ql)?://\S+"
)


def category_for_action(action) -> str:
    return ACTION_CATEGORIES.get(action, OperatorAudit.Category.PROVISIONING)


def backfill_audit_categories():
    """Set the category that matches each action. Backup stays provisioning."""
    updated = 0
    for action, category in ACTION_CATEGORIES.items():
        updated += OperatorAudit.objects.filter(action=action).exclude(
            category=category
        ).update(category=category)
    return updated


def public_audit_detail(detail) -> str:
    """Text safe to render. Hides setup passwords, database passwords, and URLs."""
    text = redact_job_error(detail or "")
    return _HIDDEN_DETAIL.sub("[redacted]", text)


def record_operator_action(*, operator=None, action, slug="", detail=""):
    return OperatorAudit.objects.create(
        operator=operator,
        action=action,
        slug=slug or "",
        detail=detail or "",
        category=category_for_action(action),
    )
