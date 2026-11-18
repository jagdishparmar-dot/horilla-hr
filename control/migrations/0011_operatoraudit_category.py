from django.db import migrations, models


def backfill_categories(apps, schema_editor):
    Audit = apps.get_model("control", "OperatorAudit")
    mapping = {
        "quota_update": "quota",
        "module_update": "quota",
        "trial_convert": "subscription",
        "invoice_issue": "billing",
        "invoice_void": "billing",
        "operator_create": "security",
        "operator_deactivate": "security",
    }
    for action, category in mapping.items():
        Audit.objects.filter(action=action).update(category=category)


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0010_invoice_ledger"),
    ]

    operations = [
        migrations.AddField(
            model_name="operatoraudit",
            name="category",
            field=models.CharField(
                choices=[
                    ("provisioning", "Provisioning"),
                    ("subscription", "Subscription"),
                    ("quota", "Quota"),
                    ("security", "Security"),
                    ("billing", "Billing"),
                ],
                default="provisioning",
                max_length=20,
            ),
        ),
        migrations.RunPython(backfill_categories, migrations.RunPython.noop),
    ]
