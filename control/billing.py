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
    """Insert one open invoice due in 14 days. No plan means no invoice.

    The tenant row is locked before the setup fee is decided, so two callers
    cannot both observe an empty invoice list and both add the fee.
    """
    if tenant.plan_fk_id is None:
        return None
    with transaction.atomic():
        tenant = Tenant.objects.select_for_update().get(pk=tenant.pk)
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
    with transaction.atomic():
        locked = Invoice.objects.select_for_update().get(pk=invoice.pk)
        if locked.status != Invoice.Status.OPEN:
            raise BillingError("Only an open invoice can be marked past due.")
        locked.status = Invoice.Status.PAST_DUE
        locked.save(update_fields=["status"])
        tenant = Tenant.objects.select_for_update().get(pk=locked.tenant_id)
        if tenant.status == Tenant.Status.ACTIVE:
            tenant.status = Tenant.Status.PAST_DUE
            tenant.save(update_fields=["status"])
    invoice.status = locked.status
    return invoice


def mark_paid(invoice):
    with transaction.atomic():
        locked = Invoice.objects.select_for_update().get(pk=invoice.pk)
        if locked.status not in (Invoice.Status.OPEN, Invoice.Status.PAST_DUE):
            raise BillingError("Only an open or past-due invoice can be marked paid.")
        locked.status = Invoice.Status.PAID
        locked.paid_on = timezone.localdate()
        locked.save(update_fields=["status", "paid_on"])
        _release_past_due(locked.tenant)
    invoice.status = locked.status
    invoice.paid_on = locked.paid_on
    return invoice


def void_invoice(invoice, operator):
    with transaction.atomic():
        locked = Invoice.objects.select_for_update().get(pk=invoice.pk)
        if locked.status not in (Invoice.Status.OPEN, Invoice.Status.PAST_DUE):
            raise BillingError("A paid invoice cannot be voided.")
        locked.status = Invoice.Status.VOID
        locked.voided_on = timezone.localdate()
        locked.save(update_fields=["status", "voided_on"])
        _release_past_due(locked.tenant)
        record_operator_action(
            operator=operator,
            action=OperatorAudit.Action.INVOICE_VOID,
            slug=locked.tenant.slug,
            detail=f"invoice {locked.pk} voided",
        )
    invoice.status = locked.status
    invoice.voided_on = locked.voided_on
    return invoice


def _release_past_due(tenant):
    """Return a past-due tenant to active when no open or past-due bill remains."""
    tenant = Tenant.objects.select_for_update().get(pk=tenant.pk)
    if tenant.status != Tenant.Status.PAST_DUE:
        return
    still_due = tenant.invoices.filter(
        status__in=(Invoice.Status.OPEN, Invoice.Status.PAST_DUE)
    ).exists()
    if still_due:
        return
    tenant.status = Tenant.Status.ACTIVE
    tenant.save(update_fields=["status"])
