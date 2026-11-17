from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0003_operator_audit"),
    ]

    operations = [
        migrations.AddField(
            model_name="tenant",
            name="setup_password_encrypted",
            field=models.TextField(blank=True),
        ),
    ]
