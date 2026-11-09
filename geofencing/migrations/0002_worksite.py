import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("base", "0001_initial"),
        ("geofencing", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="WorkSite",
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
                ("name", models.CharField(max_length=100, verbose_name="Work Site")),
                ("latitude", models.FloatField(verbose_name="Latitude")),
                ("longitude", models.FloatField(verbose_name="Longitude")),
                (
                    "radius_in_meters",
                    models.PositiveIntegerField(verbose_name="Radius in meters"),
                ),
                (
                    "start",
                    models.BooleanField(
                        default=False,
                        help_text="When enabled, employees assigned to this site can check in and check out only from inside this radius.",
                        verbose_name="Enable geofence",
                    ),
                ),
                (
                    "is_active",
                    models.BooleanField(default=True, verbose_name="Active"),
                ),
                (
                    "company_id",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="work_sites",
                        to="base.company",
                        verbose_name="Company",
                    ),
                ),
            ],
            options={
                "verbose_name": "Work Site",
                "verbose_name_plural": "Work Sites",
                "ordering": ["name"],
            },
        ),
    ]
