from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0015_provisioner_heartbeat_and_billing_audit"),
    ]

    operations = [
        migrations.AlterField(
            model_name="provisionjob",
            name="kind",
            field=models.CharField(
                choices=[
                    ("create", "Create"),
                    ("migrate", "Migrate"),
                    ("backup", "Backup"),
                    ("restore", "Restore"),
                    ("suspend", "Suspend"),
                    ("resume", "Resume"),
                    ("delete", "Delete"),
                    ("purge", "Remove"),
                ],
                max_length=20,
            ),
        ),
    ]
