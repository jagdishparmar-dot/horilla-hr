from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0002_provision_payload_and_deleted"),
    ]

    operations = [
        migrations.CreateModel(
            name="OperatorAudit",
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
                ("action", models.CharField(
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
                    ],
                    max_length=32,
                )),
                ("slug", models.CharField(blank=True, max_length=31)),
                ("detail", models.TextField(blank=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "operator",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.PROTECT,
                        related_name="audits",
                        to="control.operator",
                    ),
                ),
            ],
            options={"verbose_name": "operator audit"},
        ),
    ]
