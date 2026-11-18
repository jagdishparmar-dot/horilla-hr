from django.core.management.base import BaseCommand, CommandError

from control.models import Tenant
from control.usage import snapshot_usage


class Command(BaseCommand):
    help = "Refresh stored seat and storage snapshots from tenant databases."

    def add_arguments(self, parser):
        parser.add_argument("--slug", default="", help="Snapshot one tenant slug.")

    def handle(self, *args, **options):
        slug = (options.get("slug") or "").strip()
        if slug and not Tenant.objects.filter(slug=slug).exists():
            raise CommandError(f"No tenant {slug}.")
        errors = snapshot_usage(slug or None)
        if slug:
            self.stdout.write(f"snapshotted {slug}")
        else:
            self.stdout.write("snapshotted active and trialing tenants")
        for line in errors:
            self.stderr.write(line)
        if slug and errors:
            raise CommandError(errors[0])
