"""Validate a tenant slug. Database creation arrives in a later phase."""

from django.core.management.base import BaseCommand, CommandError

from control.naming import (
    TenantSlugError,
    tenant_database_name,
    tenant_role_name,
    validate_tenant_slug,
)


class Command(BaseCommand):
    help = (
        "Validate a tenant slug and print the database and role names. "
        "Does not create a database or a role, and does not accept a password."
    )

    def add_arguments(self, parser):
        parser.add_argument("slug", help="Tenant slug, for example acme.")

    def handle(self, *args, **options):
        try:
            slug = validate_tenant_slug(options["slug"])
        except TenantSlugError as exc:
            raise CommandError(str(exc)) from exc
        self.stdout.write(f"slug={slug}")
        self.stdout.write(f"database={tenant_database_name(slug)}")
        self.stdout.write(f"role={tenant_role_name(slug)}")
        self.stdout.write("status=accepted")
