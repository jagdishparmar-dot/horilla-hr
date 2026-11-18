from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0011_operatoraudit_category"),
    ]

    operations = [
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
