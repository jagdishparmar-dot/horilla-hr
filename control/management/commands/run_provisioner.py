"""Run queued provisioning jobs. Use only inside the single scheduler replica."""

from django.core.management.base import BaseCommand

from control.provisioning import process_available_jobs, reclaim_stale_jobs


class Command(BaseCommand):
    help = (
        "Reclaim stale provisioning jobs and run the queue one job at a time. "
        "The scheduler replica already does this every minute. Do not run a "
        "second copy."
    )

    def handle(self, *args, **options):
        reclaimed = reclaim_stale_jobs()
        processed = process_available_jobs()
        self.stdout.write(f"reclaimed={reclaimed} processed={processed}")
