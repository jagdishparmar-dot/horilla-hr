from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0013_catalog_prices"),
    ]

    operations = [
        migrations.AddField(
            model_name="operator",
            name="session_version",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AlterField(
            model_name="operatoraudit",
            name="operator",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.PROTECT,
                related_name="audits",
                to="control.operator",
            ),
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
                    ("setup_password_reset", "Setup password reset"),
                ],
                max_length=32,
            ),
        ),
    ]
