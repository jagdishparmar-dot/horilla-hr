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

    class Meta:
        verbose_name = "operator"

    def set_password(self, raw_password: str) -> None:
        self.password = make_password(raw_password)

    def check_password(self, raw_password: str) -> bool:
        return check_password(raw_password, self.password)

    def __str__(self) -> str:
        return self.email


class Tenant(models.Model):
    class Status(models.TextChoices):
        PROVISIONING = "provisioning", "Provisioning"
        ACTIVE = "active", "Active"
        SUSPENDED = "suspended", "Suspended"
        FAILED = "failed", "Failed"
        DELETING = "deleting", "Deleting"
        DELETED = "deleted", "Deleted"

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
    plan = models.CharField(max_length=64, blank=True)
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

    def set_db_password(self, plain: str) -> None:
        self.db_password_encrypted = encrypt_tenant_password(plain)

    def db_password(self) -> str:
        return decrypt_tenant_password(self.db_password_encrypted)

    def __str__(self) -> str:
        return f"{self.name} ({self.slug})"


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

    operator = models.ForeignKey(
        Operator,
        on_delete=models.PROTECT,
        related_name="audits",
    )
    action = models.CharField(max_length=32, choices=Action.choices)
    slug = models.CharField(max_length=31, blank=True)
    detail = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "operator audit"

    def save(self, *args, **kwargs):
        self.detail = redact_job_error(self.detail or "")
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.action} {self.slug}".strip()
