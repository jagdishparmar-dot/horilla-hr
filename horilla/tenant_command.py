"""Run a management command inside one tenant database."""

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import connections

from control.context import activate_tenant_alias, clear_tenant_alias
from control.db import ensure_tenant_connection
from control.models import Tenant
from control.naming import TenantSlugError, validate_tenant_slug


class TenantSlugMixin:
    """Require ``--slug`` while multi-tenant mode is on.

    With the flag off, the command keeps using the single database.
    """

    def create_parser(self, prog_name, subcommand, **kwargs):
        parser = super().create_parser(prog_name, subcommand, **kwargs)
        parser.add_argument(
            "--slug",
            default="",
            help="Tenant slug. Required when HORILLA_MULTITENANT is on.",
        )
        return parser

    def execute(self, *args, **options):
        if not getattr(settings, "HORILLA_MULTITENANT", False):
            return super().execute(*args, **options)
        raw = options.get("slug") or ""
        try:
            slug = validate_tenant_slug(raw)
        except TenantSlugError as exc:
            raise CommandError(str(exc)) from exc
        tenant = (
            Tenant.objects.filter(slug=slug)
            .exclude(status=Tenant.Status.DELETED)
            .first()
        )
        if tenant is None:
            raise CommandError(f"No tenant with slug {slug}.")
        alias = ensure_tenant_connection(tenant)
        token = activate_tenant_alias(alias)
        try:
            if not alias:
                raise CommandError("Tenant database was not selected.")
            return super().execute(*args, **options)
        finally:
            clear_tenant_alias(token)
            if alias in connections:
                connections[alias].close()


# Imported so command modules can subclass the mixin beside BaseCommand.
__all__ = ["TenantSlugMixin", "BaseCommand"]
