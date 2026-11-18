"""Run queued provisioning jobs. Deploy exactly one copy of this process."""

import signal
import time

from django.core.management.base import BaseCommand

from control.provisioning import (
    process_available_jobs,
    reclaim_stale_jobs,
    requeue_interrupted_jobs,
)

POLL_SECONDS = 5


def _expire_lapsed_trials():
    from control.trials import expire_trials

    return expire_trials()


class Command(BaseCommand):
    help = (
        "Run tenant provisioning one job at a time. On startup, a job left "
        "running for more than 30 minutes is failed. A newer interrupted job "
        "is queued again and continues from its completed steps. Do not run "
        "a second copy."
    )

    def add_arguments(self, parser):
        parser.add_argument(
            "--once",
            action="store_true",
            help="Reclaim stale jobs, requeue interrupted jobs, and drain the queue once, then exit.",
        )

    def handle(self, *args, **options):
        if options["once"]:
            self._drain_once()
            return

        stop = {"flag": False}

        def _request_stop(signum, frame):
            stop["flag"] = True
            self.stdout.write(
                f"Stopping provisioner after the current job (signal {signum})."
            )

        signal.signal(signal.SIGTERM, _request_stop)
        signal.signal(signal.SIGINT, _request_stop)
        self.stdout.write(
            "Provisioner running. A stale running job is failed. A newer one is queued again."
        )
        self._drain_once()
        while not stop["flag"]:
            # Reclaim only while idle. A migrate longer than 30 minutes is
            # still this process's current job and must not be failed here.
            reclaimed = reclaim_stale_jobs()
            _expire_lapsed_trials()
            processed = process_available_jobs()
            if processed or reclaimed:
                continue
            for _ in range(POLL_SECONDS):
                if stop["flag"]:
                    break
                try:
                    time.sleep(1)
                except InterruptedError:
                    stop["flag"] = True
        self.stdout.write("Provisioner stopped.")

    def _drain_once(self):
        # Reclaim while the row is still running. Requeue clears started_at,
        # so a stale job would otherwise look queued and never be failed.
        reclaimed = reclaim_stale_jobs()
        requeued = requeue_interrupted_jobs()
        _expire_lapsed_trials()
        processed = process_available_jobs()
        self.stdout.write(
            f"requeued={requeued} reclaimed={reclaimed} processed={processed}"
        )
