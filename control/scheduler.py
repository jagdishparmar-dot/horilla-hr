"""Control-plane schedules. Provisioning itself stays in run_provisioner.

The usage snapshot is one control-plane job. It walks active and trialing
tenants itself and keeps going when one of them fails.
"""

from horilla.scheduling import register_job


def snapshot_tenant_usage():
    from control.usage import snapshot_usage

    snapshot_usage()


register_job(
    snapshot_tenant_usage,
    "cron",
    job_id="control.snapshot_usage",
    per_tenant=False,
    hour=1,
    minute=15,
)
