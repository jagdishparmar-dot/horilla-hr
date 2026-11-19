from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0014_operator_lockout_audit"),
    ]

    operations = [
        migrations.CreateModel(
            name="ProvisionerHeartbeat",
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
                ("beat_at", models.DateTimeField()),
            ],
            options={
                "verbose_name": "provisioner heartbeat",
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
                ],
                max_length=32,
            ),
        ),
    ]
