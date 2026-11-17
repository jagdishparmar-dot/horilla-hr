"""Revoke public CONNECT on the control database."""

from django.conf import settings
from django.core.management.base import BaseCommand

from control.provisioning import lock_control_connect


class Command(BaseCommand):
    help = (
        "Revoke CONNECT on the control database from PUBLIC and from tenant "
        "roles. Does nothing while HORILLA_MULTITENANT is off."
    )

    def handle(self, *args, **options):
        if not getattr(settings, "HORILLA_MULTITENANT", False):
            self.stdout.write("HORILLA_MULTITENANT is off. Control connect lock skipped.")
            return
        lock_control_connect()
        self.stdout.write("Control database connect lock applied.")
