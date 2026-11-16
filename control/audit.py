"""Dashboard audit rows. Callers must not pass passwords or ciphertext."""

from control.models import OperatorAudit


def record_operator_action(*, operator, action, slug="", detail=""):
    return OperatorAudit.objects.create(
        operator=operator,
        action=action,
        slug=slug or "",
        detail=detail or "",
    )
