# Control hardening — immediate fixes and short-term improvements

Status: **In progress**
Owner: —
Last updated: 2026-11-19
Decision: fix the data-safety and access-control gaps found in the 2026-11-19 review before any production cutover, then the operability gaps. Tenant backups move to an **S3-compatible object store** (`BACKUP_S3_*` env vars); the local `backups/` directory becomes the spool and the dev fallback, not the system of record. Dev profile uses **RustFS** (not MinIO).

Task ids use the **R** prefix so they do not collide with `P0`–`P8` (`2026-11-16-database-per-tenant-implementation.md`) or `C0`–`C6` (`2026-11-17-control-product-redesign.md`). Review finding ids (CRIT-1, F-1, B-01, …) refer to the 2026-11-19 review.

## How to use this doc

1. Work phases in order. A task lists the earlier tasks it depends on.
2. Do not start a task whose dependencies are still open.
3. When a task is finished, check the box, set **Status** to `Done`, add the date, and append one line to the progress log.
4. If a task is blocked, set **Status** to `Blocked` and write the blocker in the progress log. Do not silently skip it.
5. A task that changes an operator page is not done until that page is exercised in the browser on the management host.

Status values: `Not started` · `In progress` · `Blocked` · `Done`

## Progress

| Phase | Tasks | Done |
| --- | ---: | ---: |
| R0. Backup store (S3) | 8 | 8 |
| R1. Console access hardening | 4 | 4 |
| R2. Operability | 10 | 10 |
| R3. Consistency and docs | 3 | 0 |
| **Total** | **25** | **22** |

### Progress log

| Date | Task | Note |
| --- | --- | --- |
| 2026-11-19 | — | Plan drafted from the control review. No code yet. |
| 2026-11-19 | R0-01 | `control/backup_store.py` + `boto3==1.40.0` in requirements. Stub-client tests cover put/get/head/list/delete, key validation, ImproperlyConfigured, secret-free errors. |
| 2026-11-19 | R0-02 | `dump_tenant_database` uploads then unlinks spool; job payload uses `dump_key`/`dump_bytes` (store) or `dump_path` (fallback); prune after backup is non-fatal. Delete stays fail-closed (tested). |
| 2026-11-19 | R0-03 | Store-first restore via private `.restore-*` spool; always unlinked; path-shaped names refused; missing object falls back to local dump. |
| 2026-11-19 | R0-04 | `_dump_file_present` HEADs `dump_key` under the tenant's own prefix; store-off or cross-slug key → false. |
| 2026-11-19 | R0-05 | Automated delete-stores-then-drops test with stub client. Live drill on local Compose + **RustFS** (`r0drill`): dump→key, restore round-trip, upload-fail refuses DROP, successful delete leaves objects. `acme`/`cldv` untouched. |
| 2026-11-19 | R0-06 | `backup_postgres` covers active/trialing/past_due/suspended; skip list documented. |
| 2026-11-19 | R0-07 | `retention_victims` / `prune_backups` / `prune_deleted_tenant_dumps` (30d); provisioner sweeps every 6h and on `--once`. |
| 2026-11-19 | R0-08 | Named `backups` volume on web/scheduler/provisioner (dev/prod/coolify). Dev profile `backups-s3` runs RustFS + bucket init. README + `.env.coolify.example` document `BACKUP_S3_*`. |
| 2026-11-19 | R1-01 | `control/lockout.py`: 5 failures per email+IP under the control cache scope, 15 min lock doubling to 24 h. Login audits `operator_login` / `operator_login_failed` (security). Unknown emails get the same message. |
| 2026-11-19 | R1-02 | `validate_operator_password` on create and change-password forms (Django validators, including email similarity). |
| 2026-11-19 | R1-03 | Staff gate on delete, purge, restore, setup-password, catalog writes, and invoice mutations. Templates hide those controls for non-staff. |
| 2026-11-19 | R1-04 | Reactivate button; change-password form (operators page + `/control/operators/password/`). Password change bumps `session_version` and cycles the session key, so other sessions stop matching. |
| 2026-11-19 | R2-01 | Newest migrate per tenant via Max(pk); failed-then-succeeded reports ok; query stays on control_provisionjob. |
| 2026-11-19 | R2-02 | Heartbeat cache + ProvisionerHeartbeat row; `/ready/` provisioner ok/stale/missing. Stopped provisioner locally → `/ready/` stale + dashboard banner within 2 minutes; restart restored ok. Fresh notice path is 0 SQL. |
| 2026-11-19 | R2-03 | Retry route/button for failed tenants; copies completed_steps; active POST returns 400; audit detail "Queued retry." |
| 2026-11-19 | R2-04 | Accepted = activated_at set (any status); suspended+activated Accepted; failed without password Not issued. |
| 2026-11-19 | R2-05 | `control.snapshot_usage` registered cron 01:15, per_tenant=False. Manual `snapshot_usage()` refreshed smile/cldv usage_updated_at. |
| 2026-11-19 | R2-06 | Restore `<select>` from list_dumps; empty → "No backups to restore"; invalid/foreign name HTTP 400. Browser queued restore for disposable `r2check` from the dropdown. |
| 2026-11-19 | R2-07 | `invoice_paid` / `invoice_past_due` / `catalog_update` audited (billing); plan create/edit/archive cover price before→after without secrets. |
| 2026-11-19 | R2-08 | Purge with invoices refused at enqueue and run ("Void or resolve…"); failed tenant without invoices still purges. |
| 2026-11-19 | R2-09 | `terminate_tenant_sessions` before restore; step=terminate at call; refuses control DB name. Live drill: held connection on disposable `tenant_r2term` terminated. |
| 2026-11-19 | R2-10 | Succeeded restore enqueues MIGRATE; failed restore enqueues nothing and holds suspended. |

## Locked decisions

- **Backups go to an S3-compatible object store.** Any provider that speaks the S3 API works (AWS S3, Cloudflare R2, Backblaze B2, MinIO, Hetzner Object Storage). The store is configured with `BACKUP_S3_*` env vars — deliberately **not** the existing media `AWS_*` vars, so turning on backup storage cannot silently move media to a bucket, and the two can use different buckets and credentials.
- **Local disk is the spool and the dev fallback.** `pg_dump` still writes to `backups/<slug>/` first, then uploads. When `BACKUP_S3_BUCKET` is unset, backups stay local — in that mode a named `backups` volume is **required** in production compose (today dumps land on the container filesystem and die on redeploy — review CRIT-1).
- **Object keys are `backups/<slug>/<timestamp>.dump`**, mirroring today's local layout. Restore and health checks resolve keys only under the tenant's own slug prefix, same rule as `resolve_dump` enforces locally today.
- **Delete stays fail-closed.** The pre-drop safety dump must be durably stored (uploaded, or written to the local volume in fallback mode) before `DROP DATABASE` runs. A failed upload fails the delete job.
- **The job payload records the dump location** (`dump_key` or `dump_path`), never credentials. `BACKUP_S3_SECRET_KEY` is read from the environment at the moment of use, like `TENANT_DB_FERNET_KEY`. It is never written to job rows, audit rows, or logs.
- **Retention is enforced by the provisioner**, not by bucket lifecycle rules, so the same policy works on every provider and in local-fallback mode. Defaults: keep the newest 7 daily and 4 weekly dumps per tenant, configurable by env.
- **Nightly backups cover every tenant whose database still holds customer data:** `active`, `trialing`, `past_due`, and `suspended`. Today only `active` is covered (review CRIT-4). Only `provisioning`, `failed`, `deleting`, and `deleted` are skipped.
- **Operator lockout is control-plane only.** The Horilla tenant login already has django-axes; the fix here protects `control-login` without touching tenant auth.
- **`is_staff` gates destructive and financial actions** (delete, purge, restore, catalog edits, invoice mutations, setup-password regeneration). A fuller role model (viewer/operator/admin) is a later plan, not this one.
- **No email in this plan.** Invites, invoice mail, and dunning stay out of scope (same boundary as the redesign plan).
- **Do not drop `acme` or `cldv`** while building this. Tests use their own slugs and mock boto3; no test may require a real bucket.

## New environment variables

| Variable | Required | Meaning |
| --- | --- | --- |
| `BACKUP_S3_BUCKET` | no — unset means local-fallback mode | Bucket name. Setting this turns the store on. |
| `BACKUP_S3_ENDPOINT_URL` | with bucket, for non-AWS providers | e.g. `https://<account>.r2.cloudflarestorage.com` or `http://minio:9000` |
| `BACKUP_S3_ACCESS_KEY` / `BACKUP_S3_SECRET_KEY` | with bucket | Credentials. Secret never logged, never in the control DB. |
| `BACKUP_S3_REGION` | provider-dependent | Default `auto`. |
| `BACKUP_S3_PREFIX` | no | Key prefix before `backups/…`, default empty. Lets one bucket serve several stacks. |
| `BACKUP_KEEP_DAILY` / `BACKUP_KEEP_WEEKLY` | no | Retention counts, default `7` / `4`. |

`boto3` is added to `requirements.txt` (django-storages 1.14.6 is already present but does not pull boto3 itself).

---

## Phase R0 — Backup store (S3-compatible)

Fixes review CRIT-1 (ephemeral backups), CRIT-4 (statuses skipped by the nightly cron), B-11 (no retention), and unblocks the restore picker in R2-06.

### [x] R0-01 Storage module and configuration contract

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** CRIT-1, B-01
- **Files:** `control/backup_store.py` (new), `requirements.txt`, `.env.coolify.example`, `docker/README.md`

One module owns all object-store access: `configured() -> bool`, `put(local_path, key)`, `get(key, local_path)`, `head(key) -> dict | None`, `list_keys(slug) -> list[dict]` (key, size, last_modified), `delete(key)`. Keys are validated against `^<prefix>backups/<slug>/[A-Za-z0-9._-]+\.dump$` before any call. When `BACKUP_S3_BUCKET` is unset every function raises `BackupStoreNotConfigured`, and callers use the local path instead. The boto3 client is built at the moment of use from the env vars; nothing is cached into Django settings.

**Done when:**
- Unit tests with a stubbed boto3 client cover put/get/head/list/delete and key validation (a key under another slug is refused).
- A missing `BACKUP_S3_SECRET_KEY` with the bucket set raises a clear `ImproperlyConfigured` at first use, mirroring `control/secrets.py`.
- The secret appears in no log line, job row, or exception message (test asserts on a forced client error).

### [x] R0-02 Dump uploads to the store

- **Status:** Done (2026-11-19)
- **Depends on:** R0-01
- **Review refs:** CRIT-1
- **Files:** `control/backup.py`, `control/provisioning.py`

`dump_tenant_database` keeps running `pg_dump` to the local spool path, then, when the store is configured: upload to `backups/<slug>/<timestamp>.dump`, record `dump_key` and `dump_bytes` on the job payload, and remove the spool file. In fallback mode the behavior is today's (`dump_path` in the payload, file kept). Upload failure raises `ProvisionError` — the backup job fails and, through the existing fail-closed rule, a delete that cannot store its safety dump does not drop the database.

**Done when:**
- A backup job in store mode leaves no file in `backups/<slug>/` and the payload names the key.
- A mocked upload failure fails the job, and a delete job with a mocked upload failure refuses to run `DROP DATABASE` (extends the existing `test_phase3` delete tests).
- The nightly cron path and the dashboard "Backup" button go through the same code (they already share `dump_tenant`).

### [x] R0-03 Restore pulls from the store

- **Status:** Done (2026-11-19)
- **Depends on:** R0-02
- **Review refs:** CRIT-1
- **Files:** `control/backup.py`

`restore_tenant_database` accepts a dump name, resolves it under this slug's prefix only, downloads to a private temp file, runs `pg_restore`, and removes the temp file in a `finally`. Fallback mode keeps today's local `resolve_dump` path. A name that is not present in the store (or local folder) stays "Dump file was not found."

**Done when:**
- A restore in store mode round-trips through a stubbed client.
- A key belonging to another slug is refused before any download (test).
- The temp file is gone after success and after a mocked `pg_restore` failure.

### [x] R0-04 Health check reads the store

- **Status:** Done (2026-11-19)
- **Depends on:** R0-02
- **Review refs:** C5-01, CRIT-1
- **Files:** `control/health.py`

`_dump_file_present` checks `dump_key` with `head()` when the payload has one, else falls back to today's local-path check. Detail text names neither the bucket nor the endpoint.

**Done when:** a healthy backup line works in both modes, and a payload whose object was deleted from the store reports "Dump file is missing."

### [x] R0-05 Pre-delete safety dump verified under the store

- **Status:** Done (2026-11-19)
- **Depends on:** R0-02, R0-03
- **Review refs:** CRIT-1, P3-07
- **Files:** `control/tests/`

No new behavior — this task is the acceptance gate. On the local Compose stack with RustFS (R0-08): create a disposable tenant, delete it, confirm the safety dump object exists, restore it into a fresh disposable tenant, then purge both.

**Done when:** the drill above is run once and recorded in the progress log, and an automated test covers delete-stores-then-drops with the stubbed client.

### [x] R0-06 Nightly backup covers all data-holding statuses

- **Status:** Done (2026-11-19)
- **Depends on:** —  (independent of the store; do not wait for R0-01)
- **Review refs:** CRIT-4, B-02
- **Files:** `pg_backup/scheduler.py`, `control/tests/`

`backup_postgres` enqueues one backup job per tenant in `active`, `trialing`, `past_due`, `suspended`. The skip list (`provisioning`, `failed`, `deleting`, `deleted`) is written as a comment next to the query.

**Done when:** a test asserts one job per tenant in each covered status and none for the skipped ones.

### [x] R0-07 Retention and pruning

- **Status:** Done (2026-11-19)
- **Depends on:** R0-02
- **Review refs:** B-11, DB-1
- **Files:** `control/backup_store.py` or `control/backup.py`, `control/management/commands/run_provisioner.py`

`prune_backups(slug)` keeps the newest `BACKUP_KEEP_DAILY` dumps plus one per ISO week up to `BACKUP_KEEP_WEEKLY`, deletes the rest, and works on both the store and the local folder. The provisioner runs it after each successful backup job for that slug. Dumps of `deleted` tenants are kept for 30 days after `deleted_at`, then pruned by a daily pass in the provisioner idle loop.

**Done when:** a test with 12 synthetic timestamps keeps the right set; a deleted tenant's dumps survive 30 days and not 31 (time-mocked test); nothing prunes when the counts are not exceeded.

### [x] R0-08 Compose, RustFS for dev, and fallback volume

- **Status:** Done (2026-11-19)
- **Depends on:** R0-01
- **Review refs:** CRIT-1, B-01
- **Files:** `docker-compose.yml`, `docker-compose.prod.yml`, `docker-compose.coolify.yml`, `docker/README.md`, `.env.coolify.example`

Three changes:
1. A named `backups` volume mounted at `/app/backups` on web, scheduler, and provisioner in **all** compose variants (prod uses `volumes: !override`, so the prod file must list it explicitly). This is the fallback mode's durability and the spool either way.
2. An optional `rustfs` service in the dev compose under a `backups-s3` profile, with a seeded `horilla-backups` bucket (`rustfs-init`), so the store path can be exercised locally. (RustFS replaced MinIO after Docker Hub/Quay pulls for MinIO were unavailable on this host.)
3. README section: env table above, fallback-mode warning ("without `BACKUP_S3_BUCKET` the backups volume is the only copy — it lives on the same host as the database"), and the restore drill from R0-05.

**Done when:** `docker compose -f docker-compose.yml config` shows the `backups` volume on all three services; a dump taken in fallback mode survives `docker compose up --force-recreate`; the RustFS profile works for the R0-05 drill.

---

## Phase R1 — Console access hardening

Fixes review CRIT-2 (unthrottled single-factor operator login) and CRIT-3 (flat authorization). MFA is deliberately out of this plan (it needs TLS first — P6-04) and goes in the next one.

### [x] R1-01 Operator login lockout and login audit

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** CRIT-2, B-03
- **Files:** `control/auth.py` or `control/lockout.py` (new), `control/views.py`, `control/models.py` (audit actions), migration

django-axes cannot see this login (it never calls `authenticate()`), so the counter is control-plane code: failures counted per `(email, client IP)` in the cache under the `control` scope, threshold 5, cooldown 15 minutes, exponential on repeat. The lockout response is the same "Email or password is not valid." message plus "Try again later." — it does not reveal whether the email exists. New audit actions `operator_login` and `operator_login_failed` (category `security`); the failed row stores the email as typed and the IP, never the password.

**Done when:**
- The 6th failure within the window is rejected before the password hash is checked (test).
- A success inside an active lockout is still rejected.
- Both audit actions appear on the Audit page under Security; a correct login writes `operator_login`.
- The counters live under the `horilla:control:` cache prefix so a tenant cannot interact with them.

### [x] R1-02 Operator password validation

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** CRIT-2, B-03
- **Files:** `control/forms.py`

`OperatorCreateForm.clean_password` runs Django's `validate_password` (length, common-password, numeric checks from `AUTH_PASSWORD_VALIDATORS`). Applies to R1-04's change-password form too.

**Done when:** `password123` and the operator's own email prefix are rejected with the validator messages; an existing strong password still passes.

### [x] R1-03 Staff gate on destructive and financial endpoints

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** CRIT-3, B-04
- **Files:** `control/views.py`, templates

Move from `@operator_required` to `@staff_required`: `tenant_delete`, `tenant_purge`, `tenant_restore`, `tenant_setup_password`, `plan_create`, `plan_edit`, `plan_delete`, `addon_create`, `addon_edit`, `addon_delete`, `invoice_past_due`, `invoice_paid`, `invoice_void`. Stays operator-level: list, detail, health, backup, migrate, suspend, resume, quota, subscription, convert, create. Templates hide the gated buttons for non-staff operators (`operator.is_staff` is already in every context via `render_control`).

**Done when:** a non-staff operator gets 403 on each gated POST (tests cover every route) and does not see the buttons; `test_phase4` and the redesign suites still pass with staff fixtures.

### [x] R1-04 Operator reactivate and self password change

- **Status:** Done (2026-11-19)
- **Depends on:** R1-02
- **Review refs:** S-4, B-17
- **Files:** `control/views.py`, `control/urls.py`, `control/templates/control/operators.html`

Two additions: a staff-only Reactivate button on inactive rows (audit `operator_reactivate`, category security), and a "Change my password" form on the operators page (visible to every operator for their own account) that requires the current password, validates with R1-02, audits `operator_password_change`, and cycles the session key.

**Done when:** a deactivated operator can be restored and can then log in; changing a password invalidates the operator's other sessions (flush other session keys or verify cycle behavior); both actions appear in the audit log without any password text.

---

## Phase R2 — Operability

### [x] R2-01 Readiness reports only the newest migrate result per tenant

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-1, B-05
- **Files:** `control/readiness.py`, tests

`tenant_migration_status` must consider, for each tenant, only its newest migrate job. Report `failed:<slug>` only when that newest job failed.

**Done when:** a tenant with a failed migrate followed by a succeeded one reports `ok`; a currently-failed tenant still reports `failed:<slug>`; the query stays on the control database.

### [x] R2-02 Provisioner heartbeat

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-2, B-06
- **Files:** `control/management/commands/run_provisioner.py`, `control/readiness.py`, `horilla/urls.py`, `control/views.py`, `control/templates/control/base.html`

Each provisioner loop iteration writes a timestamp to the cache (`horilla:control:` scope) and, as a cache-miss fallback, a single control-DB row. `/ready/` gains `"provisioner": "ok" | "stale" | "missing"` (stale after 2 minutes). The dashboard shows a banner on every page when the heartbeat is stale, including the age of the oldest queued job.

**Done when:** stopping the provisioner flips `/ready/` and shows the banner within 2 minutes on the local stack (recorded in the progress log); the KPI/banner adds at most one cheap query per request.

### [x] R2-03 Retry button for failed provisioning

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-3, B-07, P3-08
- **Files:** `control/urls.py`, `control/views.py`, `control/provisioning.py`, `control/templates/control/tenant_detail.html`

A POST route `control/tenants/<slug>/retry/` wires the existing `enqueue_retry` to a button shown only on `failed` tenants. `enqueue_retry` gains the same guard as the other enqueues (reject when a create/delete/purge job is queued or running, reject non-`failed` status) and resets the tenant to `provisioning`. Audits as `create` with detail "Queued retry."

**Done when:** a tenant failed at `migrate` retries without a second `CREATE DATABASE` (the existing `completed_steps` test extends to the view); the button is absent on `active` tenants and a raw POST on one returns 400.

### [x] R2-04 Invite state covers suspended and past-due tenants

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-9a, B-08
- **Files:** `control/setup_access.py`, tests

"Accepted" means the setup password was cleared **and** the tenant has ever been activated (`activated_at` set), regardless of current status. "Not issued" remains for pre-activation states without a password.

**Done when:** a suspended tenant whose admin completed Initialize Database shows Accepted; a failed create without a password still shows Not issued; `test_redesign_access` branches updated.

### [x] R2-05 Usage snapshots run nightly

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-5, B-09
- **Files:** `control/scheduler.py` (currently an empty placeholder), `base/management/commands/run_scheduler.py` if registration must be imported there

Register a nightly `per_tenant=False` job that calls `snapshot_usage()` (which already loops active and trialing itself and isolates per-tenant failures). The tenant list keeps reading stored columns only.

**Done when:** the job is in the scheduler registry (extend `base/tests/test_scheduling.py`), one tenant's failure leaves the others snapshotted (already tested in `test_redesign_quotas` — keep green), and the detail page's "Snapshot …" footer shows a fresh time after a local overnight or a manual trigger.

### [x] R2-06 Restore picks from a dump list

- **Status:** Done (2026-11-19)
- **Depends on:** R0-03, R0-08
- **Review refs:** F-4, B-10
- **Files:** `control/views.py`, `control/forms.py`, `control/templates/control/tenant_detail.html`

The danger-zone restore form becomes a `<select>` of this tenant's dumps (name, size, age) from `backup_store.list_keys` or, in fallback mode, the local folder. A tenant with no dumps shows "No backups to restore" and no form. Validation errors and `ProvisionError` responses return HTTP 400 (today restore errors return 200, unlike delete).

**Done when:** the dropdown lists only this slug's dumps; a raw POST with a foreign or invented name is 400; the browser check queues a restore picked from the list.

### [x] R2-07 Audit invoice payment states and catalog edits

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-6, S-6, B-12
- **Files:** `control/models.py` (actions), `control/billing.py`, `control/views.py`, `control/audit.py`, migration

New audit actions: `invoice_paid`, `invoice_past_due` (category billing — `mark_paid` and `mark_past_due` grow an `operator` argument), and `catalog_update` (category billing) written by plan/add-on create, edit, delete, and archive with a before/after price summary in the detail.

**Done when:** each action writes a row visible on the Audit page; the detail text never includes a password or connection string (existing redaction applies); `test_redesign_billing` extended.

### [x] R2-08 Purge refuses a tenant with invoices

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** F-7, B-13
- **Files:** `control/provisioning.py`, tests

`enqueue_purge` and `purge_tenant` both reject when `tenant.invoices.exists()`, with a message telling the operator to void or resolve the ledger first. (The `Invoice.tenant` FK stays `CASCADE` for row-level consistency; the guard is the policy.)

**Done when:** purge on a tenant with any invoice is refused at enqueue and at run; a failed tenant with no invoices still purges.

### [x] R2-09 Restore terminates live tenant connections first

- **Status:** Done (2026-11-19)
- **Depends on:** R0-03
- **Review refs:** DB-2, B-14
- **Files:** `control/backup.py` or `control/provisioning.py`

After the tenant is suspended and before `pg_restore`, run `pg_terminate_backend` for all sessions on that database from the maintenance cursor (excluding the maintenance connection itself, which is on the control database).

**Done when:** a restore succeeds while a deliberately-open connection holds the tenant database (integration test on the local stack, mocked in CI); the terminate step appears as `ProvisionJob.step`.

### [x] R2-10 Restore enqueues a migrate

- **Status:** Done (2026-11-19)
- **Depends on:** —
- **Review refs:** DB-3, B-15
- **Files:** `control/provisioning.py`, tests

`_run_restore` ends by inserting a queued migrate job for the same tenant, so a dump from an older release is brought to the current schema on the next provisioner pass instead of waiting for the next deploy.

**Done when:** a succeeded restore job is followed by a queued migrate job for that tenant (test), and a failed restore enqueues nothing.

---

## Phase R3 — Consistency and docs

### [ ] R3-01 Scheme-aware tenant and signup URLs

- **Status:** Not started
- **Depends on:** —
- **Review refs:** S-3, B-16
- **Files:** `horilla/settings/base.py` (`HORILLA_EXTERNAL_SCHEME`, default `http`), `control/views.py`, `control/templates/control/tenant_detail.html`, `control/templates/control/tenant_list.html`

One setting decides the scheme used for tenant-host links and the signup URL. When TLS lands (P6-04) production sets it to `https`; no template keeps a hardcoded `http://`.

**Done when:** grep finds no `http://{{` in control templates; the signup URL honors the setting; local default stays `http`.

### [ ] R3-02 Pagination

- **Status:** Not started
- **Depends on:** —
- **Review refs:** UI §7.3, B-18
- **Files:** `control/views.py`, templates

Page caps with simple prev/next: tenant directory 50 rows (tab counts keep using the full aggregate queryset, which must become a `.values("status").annotate(Count)` aggregate rather than Python iteration), tenant-detail jobs 25 with "show all", billing invoices 50, audit 100 plus a slug text filter and a from/to date filter replacing the silent 500-row cap.

**Done when:** each page renders page 2 correctly with filters preserved in the querystring; a query-count test pins the directory to a constant number of control-DB queries regardless of tenant count; the audit filter by slug returns only that tenant's rows.

### [ ] R3-03 Bring the plan documents up to date

- **Status:** Not started
- **Depends on:** —
- **Review refs:** B-19, M-15
- **Files:** `docs/plans/2026-11-16-database-per-tenant-implementation.md`, `docs/plans/2026-11-17-control-product-redesign.md`

Record what the code already does: the purge action and its rules; the `semiannual` cadence and `PlanPrice`/`AddonPrice` rows; plan/add-on CRUD on the Plans page; setup fees and per-plan trial days; price locking (`locked_plan_unit`); trial auto-expiry to `past_due` in the provisioner loop; the legacy-host redirect. Amend locked decision C4-02 to match the shipped rule (a seat-limit change on an active or past-due tenant issues an invoice) — or, if the original rule is reaffirmed, open a task to revert the code instead. Mark P3-08 as completed-by-R2-03 once the retry button lands.

**Done when:** both documents describe the shipped behavior, the C4-02 decision is explicit, and this plan is referenced from both progress logs.

---

## Suggested order inside the phases

1. **R0-06 and R2-01 through R2-04 first** — small, independent, no new infrastructure, and they close the review's highest-noise defects (missing nightly backups, stuck readiness, no retry).
2. **R0-01 → R0-02 → R0-03 → R0-04** as one arc; R0-08's compose work can proceed in parallel; **R0-05 is the gate** before calling Phase R0 done.
3. **R1 in order** — lockout before password rules before the gate before self-service.
4. **R2-06 and R2-09 wait for R0**; everything else in R2 is independent.
5. **R3 last**; R3-03 should be the final task so it records the end state.

## Out of this plan

- MFA/TOTP for operators (needs TLS on the dashboard host first — P6-04).
- Wildcard TLS and custom domains (P6-04, P4-07 — blocked on the platform-domain decision).
- Email delivery of any kind.
- Restore-verification drills against a scratch database, bucket lifecycle/off-site replication beyond the single store, and PgBouncer.
- Fernet key rotation (`MultiFernet`) — next plan.
- Seat and module enforcement inside the tenant app.
