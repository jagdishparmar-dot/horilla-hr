"""Record invoices. Nothing here charges a card or calculates GST."""

from datetime import timedelta

from django.db import transaction
from django.utils import timezone

from control.audit import record_operator_action
from control.models import Invoice, OperatorAudit, Tenant
from control.pricing import quote_tenant

INVOICE_DUE_DAYS = 14


class BillingError(Exception):
    """The invoice change is not allowed. The message is safe to show."""


def invoice_amount(tenant) -> int:
    """Whole rupees for one bill. The term follows the tenant's billing cycle.

    A setup fee is added only on the first invoice, and only when the plan
    has one. Issued rows keep ``amount_rupees`` after that.
    """
    priced = quote_tenant(tenant)
    amount = priced.term
    if (
        tenant.plan_fk_id
        and tenant.plan_fk.setup_fee_rupees
        and not tenant.invoices.exists()
    ):
        amount += int(tenant.plan_fk.setup_fee_rupees)
    return amount


def period_label(cadence, issued) -> str:
    if cadence == Tenant.Cadence.ANNUAL:
        return f"{issued.year} annual"
    if cadence == Tenant.Cadence.SEMIANNUAL:
        half = 1 if issued.month <= 6 else 2
        return f"{issued.year} H{half}"
    return issued.strftime("%B %Y")


def issue_invoice(tenant, operator):
    """Insert one open invoice due in 14 days. No plan means no invoice."""
    if tenant.plan_fk_id is None:
        return None
    issued = timezone.localdate()
    amount = invoice_amount(tenant)
    invoice = Invoice.objects.create(
        tenant=tenant,
        plan_code=tenant.plan_fk.code,
        cadence=tenant.cadence,
        seat_count=tenant.seat_limit,
        amount_rupees=amount,
        status=Invoice.Status.OPEN,
        period_label=period_label(tenant.cadence, issued),
        issued_on=issued,
        due_on=issued + timedelta(days=INVOICE_DUE_DAYS),
    )
    record_operator_action(
        operator=operator,
        action=OperatorAudit.Action.INVOICE_ISSUE,
        slug=tenant.slug,
        detail=f"invoice {invoice.pk} {amount} rupees",
    )
    return invoice


def subscription_changed(tenant, plan, cadence, addon_codes) -> bool:
    current = set(tenant.addons.values_list("code", flat=True))
    return (
        tenant.plan_fk_id != plan.pk
        or tenant.cadence != cadence
        or current != set(addon_codes)
    )


def mark_past_due(invoice):
    if invoice.status != Invoice.Status.OPEN:
        raise BillingError("Only an open invoice can be marked past due.")
    with transaction.atomic():
        invoice.status = Invoice.Status.PAST_DUE
        invoice.save(update_fields=["status"])
        tenant = invoice.tenant
        if tenant.status == Tenant.Status.ACTIVE:
            tenant.status = Tenant.Status.PAST_DUE
            tenant.save(update_fields=["status"])
    return invoice


def mark_paid(invoice):
    if invoice.status not in (Invoice.Status.OPEN, Invoice.Status.PAST_DUE):
        raise BillingError("Only an open or past-due invoice can be marked paid.")
    with transaction.atomic():
        invoice.status = Invoice.Status.PAID
        invoice.paid_on = timezone.localdate()
        invoice.save(update_fields=["status", "paid_on"])
        _release_past_due(invoice.tenant)
    return invoice


def void_invoice(invoice, operator):
    if invoice.status not in (Invoice.Status.OPEN, Invoice.Status.PAST_DUE):
        raise BillingError("A paid invoice cannot be voided.")
    with transaction.atomic():
        invoice.status = Invoice.Status.VOID
        invoice.voided_on = timezone.localdate()
        invoice.save(update_fields=["status", "voided_on"])
        _release_past_due(invoice.tenant)
        record_operator_action(
            operator=operator,
            action=OperatorAudit.Action.INVOICE_VOID,
            slug=invoice.tenant.slug,
            detail=f"invoice {invoice.pk} voided",
        )
    return invoice


def _release_past_due(tenant):
    """Return a past-due tenant to active when no open or past-due bill remains."""
    tenant.refresh_from_db()
    if tenant.status != Tenant.Status.PAST_DUE:
        return
    still_due = tenant.invoices.filter(
        status__in=(Invoice.Status.OPEN, Invoice.Status.PAST_DUE)
    ).exists()
    if still_due:
        return
    tenant.status = Tenant.Status.ACTIVE
    tenant.save(update_fields=["status"])
