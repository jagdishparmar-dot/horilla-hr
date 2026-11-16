from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    initial = True

    dependencies = []

    operations = [
        migrations.CreateModel(
            name="Operator",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("email", models.EmailField(max_length=254, unique=True)),
                ("password", models.CharField(max_length=128)),
                ("is_active", models.BooleanField(default=True)),
                ("is_staff", models.BooleanField(default=True)),
            ],
            options={"verbose_name": "operator"},
        ),
        migrations.CreateModel(
            name="Tenant",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("name", models.CharField(max_length=200)),
                ("slug", models.CharField(max_length=31, unique=True)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("provisioning", "Provisioning"),
                            ("active", "Active"),
                            ("suspended", "Suspended"),
                            ("failed", "Failed"),
                            ("deleting", "Deleting"),
                        ],
                        default="provisioning",
                        max_length=20,
                    ),
                ),
                ("db_name", models.CharField(blank=True, max_length=63)),
                ("db_user", models.CharField(blank=True, max_length=63)),
                ("db_host", models.CharField(default="db", max_length=255)),
                ("db_port", models.PositiveIntegerField(default=5432)),
                ("db_password_encrypted", models.TextField(blank=True)),
                ("plan", models.CharField(blank=True, max_length=64)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("activated_at", models.DateTimeField(blank=True, null=True)),
            ],
            options={"verbose_name": "tenant"},
        ),
        migrations.CreateModel(
            name="Domain",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("host", models.CharField(max_length=255, unique=True)),
                ("is_primary", models.BooleanField(default=False)),
                ("verified", models.BooleanField(default=False)),
                (
                    "tenant",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="domains",
                        to="control.tenant",
                    ),
                ),
            ],
            options={"verbose_name": "domain"},
        ),
        migrations.CreateModel(
            name="ProvisionJob",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                (
                    "kind",
                    models.CharField(
                        choices=[
                            ("create", "Create"),
                            ("migrate", "Migrate"),
                            ("backup", "Backup"),
                            ("restore", "Restore"),
                            ("suspend", "Suspend"),
                            ("delete", "Delete"),
                        ],
                        max_length=20,
                    ),
                ),
                ("step", models.CharField(blank=True, max_length=64)),
                (
                    "status",
                    models.CharField(
                        choices=[
                            ("queued", "Queued"),
                            ("running", "Running"),
                            ("succeeded", "Succeeded"),
                            ("failed", "Failed"),
                        ],
                        default="queued",
                        max_length=20,
                    ),
                ),
                ("error", models.TextField(blank=True)),
                ("started_at", models.DateTimeField(blank=True, null=True)),
                ("finished_at", models.DateTimeField(blank=True, null=True)),
                (
                    "tenant",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="jobs",
                        to="control.tenant",
                    ),
                ),
            ],
            options={"verbose_name": "provision job"},
        ),
    ]
