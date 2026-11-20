import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0016_alter_provisionjob_kind"),
    ]

    operations = [
        migrations.CreateModel(
            name="WorkspaceRequest",
            fields=[
                (
                    "id",
                    models.BigAutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                ("company_name", models.CharField(max_length=120)),
                ("contact_name", models.CharField(max_length=120)),
                ("email", models.EmailField()),
                ("phone", models.CharField(blank=True, max_length=32)),
                ("requested_slug", models.CharField(max_length=31)),
                ("seat_count", models.PositiveIntegerField(blank=True, null=True)),
                ("message", models.TextField(blank=True)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("new", "New"),
                            ("reviewed", "Reviewed"),
                            ("dismissed", "Dismissed"),
                        ],
                        default="new",
                        max_length=16,
                    ),
                ),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("reviewed_at", models.DateTimeField(blank=True, null=True)),
                (
                    "plan",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="workspace_requests",
                        to="control.plan",
                    ),
                ),
                (
                    "reviewed_by",
                    models.ForeignKey(
                        blank=True,
                        null=True,
                        on_delete=django.db.models.deletion.SET_NULL,
                        related_name="reviewed_requests",
                        to="control.operator",
                    ),
                ),
            ],
            options={
                "verbose_name": "workspace request",
                "ordering": ["-created_at", "-pk"],
            },
        ),
        migrations.AlterField(
            model_name="operatoraudit",
            name="action",
            field=models.CharField(
                choices=[
                    ("create", "Create"),
                    ("suspend", "Suspend"),
                    ("resume", "Resume"),
                    ("backup", "Backup"),
                    ("restore", "Restore"),
                    ("migrate", "Migrate"),
                    ("delete", "Delete"),
                    ("operator_create", "Operator create"),
                    ("operator_deactivate", "Operator deactivate"),
                    ("operator_reactivate", "Operator reactivate"),
                    ("operator_login", "Operator login"),
                    ("operator_login_failed", "Operator login failed"),
                    ("operator_password_change", "Operator password change"),
                    ("quota_update", "Quota update"),
                    ("module_update", "Module update"),
                    ("trial_convert", "Trial convert"),
                    ("invoice_issue", "Invoice issue"),
                    ("invoice_void", "Invoice void"),
                    ("invoice_paid", "Invoice paid"),
                    ("invoice_past_due", "Invoice past due"),
                    ("catalog_update", "Catalog update"),
                    ("setup_password_reset", "Setup password reset"),
                    ("request_update", "Request update"),
                ],
                max_length=32,
            ),
        ),
    ]
