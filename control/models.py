"""Control-plane registry. No Horilla HR model is imported here."""

from django.contrib.auth.hashers import check_password, make_password
from django.db import models

from control.crypto import decrypt_tenant_password, encrypt_tenant_password, redact_job_error
from control.naming import (
    assert_slug_unchanged,
    tenant_database_name,
    tenant_role_name,
    validate_tenant_slug,
)


class Operator(models.Model):
    """Dashboard login. This is not AUTH_USER_MODEL."""

    email = models.EmailField(unique=True)
    password = models.CharField(max_length=128)
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=True)
    # Bumped when the password changes so other sessions stop matching.
    session_version = models.PositiveIntegerField(default=0)

    class Meta:
        verbose_name = "operator"

    def set_password(self, raw_password: str) -> None:
        self.password = make_password(raw_password)

    def check_password(self, raw_password: str) -> bool:
        return check_password(raw_password, self.password)

    def __str__(self) -> str:
        return self.email


class ProvisionerHeartbeat(models.Model):
    """The single row the provisioner refreshes every loop."""

    beat_at = models.DateTimeField()

    class Meta:
        verbose_name = "provisioner heartbeat"

    def __str__(self) -> str:
        return self.beat_at.isoformat()


class Plan(models.Model):
    """Sellable seat price. Amounts are whole rupees, exclusive of GST.

    ``monthly_price`` stays the per-seat monthly amount so existing readers
    keep working. The price for each billing cycle lives on ``PlanPrice``.
    """

    class Status(models.TextChoices):
        ACTIVE = "active", "Active"
        INACTIVE = "inactive", "Inactive"
        ARCHIVED = "archived", "Archived"

    code = models.SlugField(max_length=32, unique=True)
    name = models.CharField(max_length=64)
    description = models.TextField(blank=True)
    monthly_price = models.PositiveIntegerField()
    seat_cap = models.PositiveIntegerField(null=True, blank=True)
    storage_gb_per_seat = models.PositiveIntegerField(null=True, blank=True)
    trial_days = models.PositiveIntegerField(default=14)
    setup_fee_rupees = models.PositiveIntegerField(default=0)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.ACTIVE,
    )
    is_active = models.BooleanField(default=True)
    sort_order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        verbose_name = "plan"
        ordering = ["sort_order", "code"]

    def __str__(self) -> str:
        return self.name


class Addon(models.Model):
    """Quote add-on. per_seat multiplies the rupee amount by the seat count.

    ``amount`` stays the monthly unit. Each billing cycle has its own row
    on ``AddonPrice``. An empty compatible-plan set means every plan.
    """

    code = models.SlugField(max_length=32, unique=True)
    name = models.CharField(max_length=120)
    description = models.TextField(blank=True)
    amount = models.PositiveIntegerField()
    per_seat = models.BooleanField(default=False)
    is_active = models.BooleanField(default=True)
    required = models.BooleanField(default=False)
    sort_order = models.PositiveSmallIntegerField(default=0)
    compatible_plans = models.ManyToManyField(
        Plan,
        blank=True,
        related_name="compatible_addons",
    )

    class Meta:
        verbose_name = "add-on"
        ordering = ["sort_order", "name"]

    def __str__(self) -> str:
        return self.name


class Tenant(models.Model):
    class Status(models.TextChoices):
        PROVISIONING = "provisioning", "Provisioning"
        ACTIVE = "active", "Active"
        TRIALING = "trialing", "Trialing"
        PAST_DUE = "past_due", "Past due"
        SUSPENDED = "suspended", "Suspended"
        FAILED = "failed", "Failed"
        DELETING = "deleting", "Deleting"
        DELETED = "deleted", "Deleted"

    # past_due still serves the tenant host. It is a billing mark, not a suspend.
    ROUTABLE_STATUSES = (Status.ACTIVE, Status.TRIALING, Status.PAST_DUE)

    class Cadence(models.TextChoices):
        MONTHLY = "monthly", "Monthly"
        SEMIANNUAL = "semiannual", "Semi-annual"
        ANNUAL = "annual", "Annual"

    name = models.CharField(max_length=200)
    slug = models.CharField(max_length=31, unique=True)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.PROVISIONING,
    )
    db_name = models.CharField(max_length=63, blank=True)
    db_user = models.CharField(max_length=63, blank=True)
    db_host = models.CharField(max_length=255, default="db")
    db_port = models.PositiveIntegerField(default=5432)
    db_password_encrypted = models.TextField(blank=True)
    # One-time password for the tenant's Initialize Database screen.
    # Cleared after the first admin is created. Never put this on __str__.
    setup_password_encrypted = models.TextField(blank=True)
    plan_fk = models.ForeignKey(
        Plan,
        null=True,
        blank=True,
        on_delete=models.PROTECT,
        related_name="tenants",
    )
    cadence = models.CharField(
        max_length=16,
        choices=Cadence.choices,
        default=Cadence.MONTHLY,
    )
    # Per-seat charge for one billing period, copied when the subscription is saved.
    # Catalog edits do not change this. Null means "use the current catalog".
    locked_plan_unit = models.PositiveIntegerField(null=True, blank=True)
    addons = models.ManyToManyField(
        Addon,
        through="TenantAddon",
        blank=True,
        related_name="tenants",
    )
    seat_limit = models.PositiveIntegerField(default=25)
    storage_limit_gb = models.PositiveIntegerField(default=0)
    active_seats = models.PositiveIntegerField(default=0)
    used_storage_gb = models.PositiveIntegerField(default=0)
    usage_updated_at = models.DateTimeField(null=True, blank=True)
    module_employee_records = models.BooleanField(default=True)
    module_payroll_engine = models.BooleanField(default=True)
    module_performance_reviews = models.BooleanField(default=True)
    industry = models.CharField(max_length=120, blank=True)
    admin_name = models.CharField(max_length=200, blank=True)
    admin_email = models.EmailField(blank=True)
    trial_ends_at = models.DateTimeField(null=True, blank=True)
    suspension_reason = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    activated_at = models.DateTimeField(null=True, blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "tenant"

    def save(self, *args, **kwargs):
        self.slug = validate_tenant_slug(self.slug)
        if self.pk:
            previous = (
                Tenant.objects.filter(pk=self.pk).values_list("slug", flat=True).first()
            )
            if previous is not None:
                assert_slug_unchanged(previous, self.slug)
        if not self.db_name:
            self.db_name = tenant_database_name(self.slug)
        if not self.db_user:
            self.db_user = tenant_role_name(self.slug)
        super().save(*args, **kwargs)

    def module_names(self) -> list[str]:
        names = []
        if self.module_employee_records:
            names.append("Employee records")
        if self.module_payroll_engine:
            names.append("Payroll engine")
        if self.module_performance_reviews:
            names.append("Performance reviews")
        return names

    def set_db_password(self, plain: str) -> None:
        self.db_password_encrypted = encrypt_tenant_password(plain)

    def db_password(self) -> str:
        return decrypt_tenant_password(self.db_password_encrypted)

    def set_setup_password(self, plain: str) -> None:
        self.setup_password_encrypted = encrypt_tenant_password(plain)

    def setup_password(self) -> str:
        return decrypt_tenant_password(self.setup_password_encrypted)

    @property
    def plan_label(self) -> str:
        plan = self.plan_fk
        return plan.name if plan is not None else "Unassigned"

    def __str__(self) -> str:
        return f"{self.name} ({self.slug})"


class TenantAddon(models.Model):
    tenant = models.ForeignKey(
        Tenant,
        on_delete=models.CASCADE,
        related_name="subscription_addons",
    )
    addon = models.ForeignKey(
        Addon,
        on_delete=models.PROTECT,
        related_name="subscriptions",
    )
    # Charge for one billing period at the time the subscription was saved.
    locked_unit = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        verbose_name = "tenant add-on"
        constraints = [
            models.UniqueConstraint(
                fields=["tenant", "addon"],
                name="control_tenant_addon_unique",
            )
        ]

    def __str__(self) -> str:
        return f"{self.tenant_id}:{self.addon_id}"


class PlanPrice(models.Model):
    """Per-seat charge for one billing period of a plan."""

    plan = models.ForeignKey(Plan, on_delete=models.CASCADE, related_name="prices")
    cadence = models.CharField(max_length=16, choices=Tenant.Cadence.choices)
    unit_rupees = models.PositiveIntegerField()

    class Meta:
        verbose_name = "plan price"
        constraints = [
            models.UniqueConstraint(
                fields=["plan", "cadence"],
                name="control_plan_price_cadence",
            )
        ]

    def __str__(self) -> str:
        return f"{self.plan_id} {self.cadence}"


class AddonPrice(models.Model):
    """Charge for one billing period. Per-seat add-ons multiply this by seats."""

    addon = models.ForeignKey(Addon, on_delete=models.CASCADE, related_name="prices")
    cadence = models.CharField(max_length=16, choices=Tenant.Cadence.choices)
    unit_rupees = models.PositiveIntegerField()

    class Meta:
        verbose_name = "add-on price"
        constraints = [
            models.UniqueConstraint(
                fields=["addon", "cadence"],
                name="control_addon_price_cadence",
            )
        ]

    def __str__(self) -> str:
        return f"{self.addon_id} {self.cadence}"


class Domain(models.Model):
    tenant = models.ForeignKey(
        Tenant,
        on_delete=models.CASCADE,
        related_name="domains",
    )
    host = models.CharField(max_length=255, unique=True)
    is_primary = models.BooleanField(default=False)
    verified = models.BooleanField(default=False)

    class Meta:
        verbose_name = "domain"

    def __str__(self) -> str:
        return self.host


class ProvisionJob(models.Model):
    class Kind(models.TextChoices):
        CREATE = "create", "Create"
        MIGRATE = "migrate", "Migrate"
        BACKUP = "backup", "Backup"
        RESTORE = "restore", "Restore"
        SUSPEND = "suspend", "Suspend"
        RESUME = "resume", "Resume"
        DELETE = "delete", "Delete"
        PURGE = "purge", "Remove"

    class Status(models.TextChoices):
        QUEUED = "queued", "Queued"
        RUNNING = "running", "Running"
        SUCCEEDED = "succeeded", "Succeeded"
        FAILED = "failed", "Failed"

    tenant = models.ForeignKey(
        Tenant,
        on_delete=models.CASCADE,
        related_name="jobs",
    )
    kind = models.CharField(max_length=20, choices=Kind.choices)
    step = models.CharField(max_length=64, blank=True)
    status = models.CharField(
        max_length=20,
        choices=Status.choices,
        default=Status.QUEUED,
    )
    error = models.TextField(blank=True)
    payload = models.JSONField(default=dict, blank=True)
    started_at = models.DateTimeField(null=True, blank=True)
    finished_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        verbose_name = "provision job"

    def set_error(self, message: str) -> None:
        self.error = redact_job_error(message)

    def __str__(self) -> str:
        return f"{self.kind} {self.status} ({self.tenant.slug})"


class OperatorAudit(models.Model):
    """Who changed a tenant or an operator. Never store a password here."""

    class Action(models.TextChoices):
        CREATE = "create", "Create"
        SUSPEND = "suspend", "Suspend"
        RESUME = "resume", "Resume"
        BACKUP = "backup", "Backup"
        RESTORE = "restore", "Restore"
        MIGRATE = "migrate", "Migrate"
        DELETE = "delete", "Delete"
        OPERATOR_CREATE = "operator_create", "Operator create"
        OPERATOR_DEACTIVATE = "operator_deactivate", "Operator deactivate"
        OPERATOR_REACTIVATE = "operator_reactivate", "Operator reactivate"
        OPERATOR_LOGIN = "operator_login", "Operator login"
        OPERATOR_LOGIN_FAILED = "operator_login_failed", "Operator login failed"
        OPERATOR_PASSWORD_CHANGE = "operator_password_change", "Operator password change"
        QUOTA_UPDATE = "quota_update", "Quota update"
        MODULE_UPDATE = "module_update", "Module update"
        TRIAL_CONVERT = "trial_convert", "Trial convert"
        INVOICE_ISSUE = "invoice_issue", "Invoice issue"
        INVOICE_VOID = "invoice_void", "Invoice void"
        INVOICE_PAID = "invoice_paid", "Invoice paid"
        INVOICE_PAST_DUE = "invoice_past_due", "Invoice past due"
        CATALOG_UPDATE = "catalog_update", "Catalog update"
        SETUP_PASSWORD_RESET = "setup_password_reset", "Setup password reset"
        REQUEST_UPDATE = "request_update", "Request update"

    class Category(models.TextChoices):
        PROVISIONING = "provisioning", "Provisioning"
        SUBSCRIPTION = "subscription", "Subscription"
        QUOTA = "quota", "Quota"
        SECURITY = "security", "Security"
        BILLING = "billing", "Billing"

    operator = models.ForeignKey(
        Operator,
        on_delete=models.PROTECT,
        related_name="audits",
        null=True,
        blank=True,
    )
    action = models.CharField(max_length=32, choices=Action.choices)
    category = models.CharField(
        max_length=20,
        choices=Category.choices,
        default=Category.PROVISIONING,
    )
    slug = models.CharField(max_length=31, blank=True)
    detail = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "operator audit"

    def save(self, *args, **kwargs):
        from control.audit import category_for_action

        self.detail = redact_job_error(self.detail or "")
        self.category = category_for_action(self.action)
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.action} {self.slug}".strip()


class Invoice(models.Model):
    """A recorded bill. This table does not store a card, a secret, or GST."""

    class Status(models.TextChoices):
        OPEN = "open", "Open"
        PAID = "paid", "Paid"
        PAST_DUE = "past_due", "Past due"
        VOID = "void", "Void"

    tenant = models.ForeignKey(
        Tenant,
        on_delete=models.CASCADE,
        related_name="invoices",
    )
    plan_code = models.SlugField(max_length=32)
    cadence = models.CharField(max_length=16, choices=Tenant.Cadence.choices)
    seat_count = models.PositiveIntegerField()
    amount_rupees = models.PositiveIntegerField()
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.OPEN,
    )
    period_label = models.CharField(max_length=80)
    issued_on = models.DateField()
    due_on = models.DateField()
    paid_on = models.DateField(null=True, blank=True)
    voided_on = models.DateField(null=True, blank=True)

    class Meta:
        verbose_name = "invoice"
        ordering = ["-issued_on", "-pk"]

    def __str__(self) -> str:
        return f"{self.pk} {self.tenant.slug} {self.status}"


class WorkspaceRequest(models.Model):
    """A public request for a workspace. Operators provision it by hand."""

    class Status(models.TextChoices):
        NEW = "new", "New"
        REVIEWED = "reviewed", "Reviewed"
        DISMISSED = "dismissed", "Dismissed"

    company_name = models.CharField(max_length=120)
    contact_name = models.CharField(max_length=120)
    email = models.EmailField()
    phone = models.CharField(max_length=32, blank=True)
    requested_slug = models.CharField(max_length=31)
    plan = models.ForeignKey(
        Plan,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="workspace_requests",
    )
    seat_count = models.PositiveIntegerField(null=True, blank=True)
    message = models.TextField(blank=True)
    status = models.CharField(
        max_length=16,
        choices=Status.choices,
        default=Status.NEW,
    )
    created_at = models.DateTimeField(auto_now_add=True)
    reviewed_at = models.DateTimeField(null=True, blank=True)
    reviewed_by = models.ForeignKey(
        Operator,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="reviewed_requests",
    )

    class Meta:
        verbose_name = "workspace request"
        ordering = ["-created_at", "-pk"]

    def __str__(self) -> str:
        return f"{self.company_name} ({self.requested_slug})"
