import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("attendance", "0014_attendanceactivity_punch_location"),
        ("geofencing", "0002_worksite"),
    ]

    operations = [
        migrations.AddField(
            model_name="historicalattendanceactivity",
            name="work_site",
            field=models.ForeignKey(
                blank=True,
                db_constraint=False,
                null=True,
                on_delete=django.db.models.deletion.DO_NOTHING,
                related_name="+",
                to="geofencing.worksite",
                verbose_name="Work Site",
            ),
        ),
        migrations.AddField(
            model_name="historicalattendanceactivity",
            name="clock_in_latitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-in latitude"
            ),
        ),
        migrations.AddField(
            model_name="historicalattendanceactivity",
            name="clock_in_longitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-in longitude"
            ),
        ),
        migrations.AddField(
            model_name="historicalattendanceactivity",
            name="clock_out_latitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-out latitude"
            ),
        ),
        migrations.AddField(
            model_name="historicalattendanceactivity",
            name="clock_out_longitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-out longitude"
            ),
        ),
    ]
