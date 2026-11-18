from django.db import migrations


def drop_plan_label(apps, schema_editor):
    """Drop the free-text column when it is still present.

    A database that already applied an earlier draft of 0006 has no column left.
    """
    with schema_editor.connection.cursor() as cursor:
        description = schema_editor.connection.introspection.get_table_description(
            cursor, "control_tenant"
        )
    if "plan" not in {column.name for column in description}:
        return
    schema_editor.execute("ALTER TABLE control_tenant DROP COLUMN plan")


class Migration(migrations.Migration):

    dependencies = [
        ("control", "0006_move_plan_labels"),
    ]

    operations = [
        migrations.SeparateDatabaseAndState(
            state_operations=[
                migrations.RemoveField(
                    model_name="tenant",
                    name="plan",
                ),
            ],
            database_operations=[
                migrations.RunPython(drop_plan_label, migrations.RunPython.noop),
            ],
        ),
    ]
