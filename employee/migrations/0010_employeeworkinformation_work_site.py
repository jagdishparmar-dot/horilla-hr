import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("employee", "0009_alter_actiontype_is_active_and_more"),
        ("geofencing", "0002_worksite"),
    ]

    operations = [
        migrations.AddField(
            model_name="employeeworkinformation",
            name="work_site",
            field=models.ForeignKey(
                blank=True,
                help_text="When this site has geofencing enabled, check-in and check-out are allowed only inside that site.",
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="assigned_employees",
                to="geofencing.worksite",
                verbose_name="Work Site",
            ),
        ),
    ]
