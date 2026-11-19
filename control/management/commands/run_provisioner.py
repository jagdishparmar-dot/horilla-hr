"""Run queued provisioning jobs. Deploy exactly one copy of this process."""

import logging
import signal
import time

from django.core.management.base import BaseCommand

from control.provisioning import (
    process_available_jobs,
    reclaim_stale_jobs,
    requeue_interrupted_jobs,
)

POLL_SECONDS = 5
# Dumps of deleted tenants are swept at startup and then every six hours.
SWEEP_SECONDS = 6 * 60 * 60

logger = logging.getLogger(__name__)

_next_sweep = 0.0


def _beat() -> None:
    from control.heartbeat import beat

    try:
        beat()
    except Exception:  # noqa: BLE001 - a missed beat must not stop the worker
        logger.exception("Provisioner heartbeat failed.")


def _expire_lapsed_trials():
    from control.trials import expire_trials

    return expire_trials()


def _sweep_deleted_dumps(force=False) -> int:
    """Prune dumps of long-deleted tenants. Never interrupts job processing."""
    global _next_sweep
    now = time.monotonic()
    if not force and now < _next_sweep:
        return 0
    _next_sweep = now + SWEEP_SECONDS
    from control.backup import prune_deleted_tenant_dumps

    try:
        return prune_deleted_tenant_dumps()
    except Exception:  # noqa: BLE001 - the sweep must not stop the worker
        logger.exception("Deleted-tenant dump sweep failed.")
        return 0


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
            _beat()
            reclaimed = reclaim_stale_jobs()
            _expire_lapsed_trials()
            _sweep_deleted_dumps()
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
        _beat()
        reclaimed = reclaim_stale_jobs()
        requeued = requeue_interrupted_jobs()
        _expire_lapsed_trials()
        swept = _sweep_deleted_dumps(force=True)
        processed = process_available_jobs()
        self.stdout.write(
            f"requeued={requeued} reclaimed={reclaimed} processed={processed} "
            f"swept={swept}"
        )
