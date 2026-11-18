from django.db import migrations, models


def seed_cycle_prices(apps, schema_editor):
    from control.catalog import cycle_amounts

    Plan = apps.get_model("control", "Plan")
    Addon = apps.get_model("control", "Addon")
    PlanPrice = apps.get_model("control", "PlanPrice")
    AddonPrice = apps.get_model("control", "AddonPrice")
    Tenant = apps.get_model("control", "Tenant")
    TenantAddon = apps.get_model("control", "TenantAddon")
    for plan in Plan.objects.all():
        if plan.is_active:
            plan.status = "active"
        else:
            plan.status = "inactive"
        plan.trial_days = 14
        plan.setup_fee_rupees = 0
        plan.save(update_fields=["status", "trial_days", "setup_fee_rupees"])
        for cadence, amount in cycle_amounts(plan.monthly_price).items():
            PlanPrice.objects.update_or_create(
                plan=plan,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )
    for addon in Addon.objects.all():
        for cadence, amount in cycle_amounts(addon.amount).items():
            AddonPrice.objects.update_or_create(
                addon=addon,
                cadence=cadence,
                defaults={"unit_rupees": amount},
            )
    for tenant in Tenant.objects.exclude(plan_fk=None):
        unit = (
            PlanPrice.objects.filter(plan_id=tenant.plan_fk_id, cadence=tenant.cadence)
            .values_list("unit_rupees", flat=True)
            .first()
        )
        tenant.locked_plan_unit = unit
        tenant.save(update_fields=["locked_plan_unit"])
        for link in TenantAddon.objects.filter(tenant=tenant):
            addon_unit = (
                AddonPrice.objects.filter(addon_id=link.addon_id, cadence=tenant.cadence)
                .values_list("unit_rupees", flat=True)
                .first()
            )
            link.locked_unit = addon_unit
            link.save(update_fields=["locked_unit"])


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0012_setup_password_reset"),
    ]

    operations = [
        migrations.AddField(
            model_name="plan",
            name="description",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="plan",
            name="setup_fee_rupees",
            field=models.PositiveIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="plan",
            name="status",
            field=models.CharField(
                choices=[
                    ("active", "Active"),
                    ("inactive", "Inactive"),
                    ("archived", "Archived"),
                ],
                default="active",
                max_length=16,
            ),
        ),
        migrations.AddField(
            model_name="plan",
            name="trial_days",
            field=models.PositiveIntegerField(default=14),
        ),
        migrations.AddField(
            model_name="addon",
            name="description",
            field=models.TextField(blank=True),
        ),
        migrations.AddField(
            model_name="addon",
            name="is_active",
            field=models.BooleanField(default=True),
        ),
        migrations.AddField(
            model_name="addon",
            name="required",
            field=models.BooleanField(default=False),
        ),
        migrations.AddField(
            model_name="addon",
            name="sort_order",
            field=models.PositiveSmallIntegerField(default=0),
        ),
        migrations.AddField(
            model_name="tenant",
            name="locked_plan_unit",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AddField(
            model_name="tenantaddon",
            name="locked_unit",
            field=models.PositiveIntegerField(blank=True, null=True),
        ),
        migrations.AlterModelOptions(
            name="addon",
            options={"ordering": ["sort_order", "name"], "verbose_name": "add-on"},
        ),
        migrations.AlterField(
            model_name="tenant",
            name="cadence",
            field=models.CharField(
                choices=[
                    ("monthly", "Monthly"),
                    ("semiannual", "Semi-annual"),
                    ("annual", "Annual"),
                ],
                default="monthly",
                max_length=16,
            ),
        ),
        migrations.AlterField(
            model_name="invoice",
            name="cadence",
            field=models.CharField(
                choices=[
                    ("monthly", "Monthly"),
                    ("semiannual", "Semi-annual"),
                    ("annual", "Annual"),
                ],
                max_length=16,
            ),
        ),
        migrations.CreateModel(
            name="PlanPrice",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("cadence", models.CharField(choices=[("monthly", "Monthly"), ("semiannual", "Semi-annual"), ("annual", "Annual")], max_length=16)),
                ("unit_rupees", models.PositiveIntegerField()),
                ("plan", models.ForeignKey(on_delete=models.deletion.CASCADE, related_name="prices", to="control.plan")),
            ],
            options={"verbose_name": "plan price"},
        ),
        migrations.CreateModel(
            name="AddonPrice",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("cadence", models.CharField(choices=[("monthly", "Monthly"), ("semiannual", "Semi-annual"), ("annual", "Annual")], max_length=16)),
                ("unit_rupees", models.PositiveIntegerField()),
                ("addon", models.ForeignKey(on_delete=models.deletion.CASCADE, related_name="prices", to="control.addon")),
            ],
            options={"verbose_name": "add-on price"},
        ),
        migrations.AddField(
            model_name="addon",
            name="compatible_plans",
            field=models.ManyToManyField(blank=True, related_name="compatible_addons", to="control.plan"),
        ),
        migrations.AddConstraint(
            model_name="planprice",
            constraint=models.UniqueConstraint(fields=("plan", "cadence"), name="control_plan_price_cadence"),
        ),
        migrations.AddConstraint(
            model_name="addonprice",
            constraint=models.UniqueConstraint(fields=("addon", "cadence"), name="control_addon_price_cadence"),
        ),
        migrations.RunPython(seed_cycle_prices, migrations.RunPython.noop),
    ]
