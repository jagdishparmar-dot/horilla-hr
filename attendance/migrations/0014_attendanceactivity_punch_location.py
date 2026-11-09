import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("attendance", "0013_alter_attendanceconflictresolution_resolution"),
        ("geofencing", "0002_worksite"),
    ]

    operations = [
        migrations.AddField(
            model_name="attendanceactivity",
            name="work_site",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="attendance_activities",
                to="geofencing.worksite",
                verbose_name="Work Site",
            ),
        ),
        migrations.AddField(
            model_name="attendanceactivity",
            name="clock_in_latitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-in latitude"
            ),
        ),
        migrations.AddField(
            model_name="attendanceactivity",
            name="clock_in_longitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-in longitude"
            ),
        ),
        migrations.AddField(
            model_name="attendanceactivity",
            name="clock_out_latitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-out latitude"
            ),
        ),
        migrations.AddField(
            model_name="attendanceactivity",
            name="clock_out_longitude",
            field=models.FloatField(
                blank=True, null=True, verbose_name="Check-out longitude"
            ),
        ),
    ]
