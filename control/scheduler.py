"""Queue worker for tenant provisioning. Loaded only by run_scheduler."""

from horilla.scheduling import register_job


def provision_queued_tenants():
    from control.provisioning import process_available_jobs, reclaim_stale_jobs

    reclaim_stale_jobs()
    process_available_jobs()


register_job(provision_queued_tenants, "interval", minutes=1)
