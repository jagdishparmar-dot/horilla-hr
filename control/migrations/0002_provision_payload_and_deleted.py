from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0001_initial"),
    ]

    operations = [
        migrations.AddField(
            model_name="tenant",
            name="deleted_at",
            field=models.DateTimeField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="provisionjob",
            name="payload",
            field=models.JSONField(blank=True, default=dict),
        ),
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
                ],
                max_length=20,
            ),
        ),
        migrations.AlterField(
            model_name="tenant",
            name="status",
            field=models.CharField(
                choices=[
                    ("provisioning", "Provisioning"),
                    ("active", "Active"),
                    ("suspended", "Suspended"),
                    ("failed", "Failed"),
                    ("deleting", "Deleting"),
                    ("deleted", "Deleted"),
                ],
                default="provisioning",
                max_length=20,
            ),
        ),
    ]
