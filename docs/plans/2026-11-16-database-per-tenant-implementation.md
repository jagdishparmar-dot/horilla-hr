# Database-per-tenant SaaS — implementation plan

Status: **Draft**
Owner: —
Last updated: 2026-11-16
Decision: one shared Horilla web application, **one PostgreSQL database per customer**, plus a small control database for the registry and the provisioning dashboard.

This document is the tracker. Flip a task from `[ ]` to `[x]` when its acceptance checks pass. Leave the detail under the task so the next person can see what “done” meant.

## How to use this doc

1. Work phases in order. A task lists the earlier tasks it depends on.
2. Do not start a task whose dependencies are still open.
3. When a task is finished, check the box, set **Status** to `Done`, add the date, and append one line to the progress log.
4. If a task is blocked, set **Status** to `Blocked` and write the blocker in the progress log. Do not silently skip it.
5. Horilla `Company` stays an organization **inside** a customer. It is not the SaaS tenant.

Status values: `Not started` · `In progress` · `Blocked` · `Done`

## Progress

| Phase | Tasks | Done |
| --- | ---: | ---: |
| 0. Guardrails | 4 | 4 |
| 1. Control plane | 6 | 6 |
| 2. Request routing | 7 | 7 |
| 3. Provisioning engine | 8 | 8 |
| 4. Operator dashboard | 8 | 7 |
| 5. Runtime isolation | 7 | 7 |
| 6. Deploy and hosts | 6 | 5 |
| 7. Isolation tests | 6 | 6 |
| 8. Cutover | 5 | 5 |
| **Total** | **57** | **55** |

### Progress log

| Date | Task | Note |
| --- | --- | --- |
| 2026-11-16 | — | Plan drafted from the database-per-tenant design. No code yet. |
| 2026-11-16 | P0 | Guardrails committed on `feature/database-per-tenant`. Local hosts are `<slug>.localhost` and `manage.localhost`. Production domain stays in `HORILLA_PLATFORM_DOMAIN`. |
| 2026-11-16 | P1 | Control models, Fernet password storage, router, and `migrate_tenants` are in place. Strict routing stays off until `HORILLA_MULTITENANT` is enabled. 23 control tests passed. |
| 2026-11-16 | P2 | Host routing is in place and stays off until `HORILLA_MULTITENANT` is enabled. Dashboard and tenant URL confs are separate. |
| 2026-11-16 | P3 | Provisioning jobs run in the single scheduler replica. Create, suspend, resume, retry, and delete are queued. Delete keeps the tenant row as `deleted` and refuses to drop a database until P5 supplies `pg_dump`. 11 phase-3 tests passed. |
| 2026-11-16 | P4 | Operator dashboard is on the management host with cookie `control_sessionid`. Create, suspend, resume, backup, migrate, restore, and delete only enqueue jobs. Backup, migrate, and restore stay queued until phase 5. P4-07 stays open until custom-domain nginx exists. 7 phase-4 tests passed. |
| 2026-11-16 | P5 | Cache, uploads, media downloads, scheduler, backups, restore, and JWT are tenant-scoped. Scheduler policy is log and continue. HR management commands require `--slug` when the flag is on. `pg_dump` is in the image only after the next rebuild; tests mock the binary. P4-07 stays open. |
| 2026-11-16 | P6 | Web and scheduler share the control `DATABASE_URL`. Nginx accepts `manage.<domain>` and `*.<domain>` and forwards `Host`. The scheduler waits until web has migrated. P6-04 is blocked: no platform domain, so the wildcard certificate is not issued. P4-07 stays open. |
| 2026-11-17 | P7 | Isolation suite `control.tests.test_phase7` passed on the local Compose stack: same email and badge, cross-tenant primary key 404, session cookie not portable, cache and media refused across slugs, scheduler abort without an alias, and `tenant_p7isob` cannot connect to `tenant_p7isoa`. |
| 2026-11-17 | P8 | Local cutover. `horilla_db` was dumped and left in place. This install now uses `horilla_control` and the existing `tenant_cldv` (Coldverse) and `tenant_acme`. Bare `localhost` redirects to `cldv.localhost`. `/health/` stays 200. A person still has to read the rollback before any production cutover. P4-07 and P6-04 stay open. |

## Locked decisions

- **Tenant boundary** is a PostgreSQL database and a dedicated login role that can `CONNECT` only to that database. The web process connects as that role, never as a superuser.
- **Control database** (`default`, from `DATABASE_URL`) stores operators, tenants, domains, and job logs. It does not store employees, payroll, attendance, or files metadata for a customer.
- **Tenant database** gets the current Horilla schema, including `horilla_auth.HorillaUser`. Models do not grow a `tenant_id` column.
- **Dashboard host** is a fixed hostname (`manage.<platform-domain>`). Tenant subdomains never serve dashboard routes.
- **Dashboard users** are `control.Operator`. `AUTH_USER_MODEL` stays `horilla_auth.HorillaUser` and is migrated only into tenant databases.
- **Existing company filter** (`HorillaCompanyManager`, `CompanyMiddleware`) keeps working inside the tenant database. “All companies” means all companies of that customer.
- **One scheduler replica** remains. Its job store stays in the control database. Each run loops active tenants and opens that tenant’s database for the body of the job.
- **Compose shape stays** one `web`, one `scheduler`, one `db`, one `redis`, one `nginx`. Customers are databases, not containers.
- **Mobile** already stores a server URL on the device (`flutter_app/lib/core/config.dart`). Each customer points the app at their own host. No store build per customer in this plan.

## Current code this plan touches

| Area | File | What changes |
| --- | --- | --- |
| Settings | `horilla/settings/base.py` | `DATABASES`, `CACHES["default"]["KEY_PREFIX"]`, `MIDDLEWARE`, `ALLOWED_HOSTS` |
| Startup | `docker/entrypoint.sh` | `migrate` must target the control database, then active tenant databases |
| Compose | `docker-compose.yml`, `docker-compose.prod.yml` | Control `DATABASE_URL`, Postgres role split, nginx wildcard host |
| Scheduler | `base/management/commands/run_scheduler.py` | Job store on control DB; job bodies enter a tenant alias |
| Company scope | `base/middleware.py`, `base/horilla_company_manager.py` | Unchanged behavior, but only after the tenant database is selected |
| Health | `horilla/urls.py` | Readiness checks the control database; it must not open an arbitrary tenant |
| Backups | `horilla_backup/`, `pg_backup/` | Dump one named database per tenant |
| Media | `MEDIA_ROOT` in `horilla/settings/base.py` | Prefix `media/<slug>/` |

## Target request flow

```text
Host: acme.clockme.example
        │
        ▼
TenantMiddleware
  lookup Domain in control DB
  reject unknown / suspended
  register alias tenant_acme with that tenant's DB role
        │
        ▼
CompanyMiddleware          (existing; companies inside this database)
AuthenticationMiddleware
Horilla views / API
        │
        ▼
close tenant connection

Host: manage.clockme.example
        │
        ▼
Control URL conf only
Operator session
No tenant alias is opened
```

## Target data layout

```text
PostgreSQL instance (existing db service)
├── horilla_control          control role only
│     Operator, Tenant, Domain, ProvisionJob
└── tenant_<slug>            role tenant_<slug> only
      full Horilla schema (employees, payroll, attendance, …)

Redis (shared)
└── keys: horilla:<slug>:<key>

Media volume (shared)
└── media/<slug>/...

Backups
└── backups/<slug>/<timestamp>.dump
```

---

## Phase 0 — Guardrails

### [x] P0-01 Confirm platform domain and dashboard host

- **Status:** Done (2026-11-16)
- **Depends on:** —
- **Done when:**
  - Platform domain, dashboard host, and subdomain pattern are written in this section (replace the placeholders below).
  - Cookie policy is recorded: host-only cookies, `SESSION_COOKIE_DOMAIN = None`, `CSRF_COOKIE_DOMAIN = None`.

No production domain is configured in this repo (`.env` is localhost and a LAN address). The platform domain is therefore an environment setting, not a hardcoded hostname.

| Item | Value |
| --- | --- |
| Platform domain | `HORILLA_PLATFORM_DOMAIN`, default `localhost` |
| Dashboard host | `HORILLA_DASHBOARD_HOST`, default `manage.<platform-domain>` (`manage.localhost` locally) |
| Tenant host | `<slug>.<platform-domain>` (`acme.localhost` locally) |
| Custom domains | Supported after DNS verification, not in the first milestone |
| Cookies | `SESSION_COOKIE_DOMAIN = None` and `CSRF_COOKIE_DOMAIN = None` in `horilla/settings/base.py` |

### [x] P0-02 Record slug and database naming rules

- **Status:** Done (2026-11-16)
- **Depends on:** P0-01
- **Done when:** the rules below are accepted and the provisioning command rejects anything else.

Implemented in `control/naming.py`. `python manage.py provision_tenant <slug>` rejects a bad slug and, for a valid one, prints `tenant_<slug>` without creating a database. Mixed case is normalized to lower case. Phase 3 must keep calling `validate_tenant_slug`.

Rules to implement later, unchanged unless this box is edited:

- Slug matches `^[a-z][a-z0-9_]{2,30}$`.
- Database name and role name are `tenant_<slug>`.
- Reserved names are rejected: `postgres`, `template0`, `template1`, `horilla_control`, `default`, `public`.
- Slug is immutable after the database exists. Renames are a new tenant plus a restore, not `ALTER DATABASE` from the dashboard.

### [x] P0-03 Choose secret storage for tenant DB passwords

- **Status:** Done (2026-11-16)
- **Depends on:** —
- **Done when:**
  - An env var name is chosen (proposed: `TENANT_DB_FERNET_KEY`).
  - The key is documented as required in production and absent from git.
  - Tenant passwords are never written to logs, job output, or the media volume.

`TENANT_DB_FERNET_KEY` is required only when `HORILLA_MULTITENANT` is true, so the current single-tenant stack still starts. The key is not copied into Django settings. Documented in `.env.coolify.example` and `docker/README.md` with an empty value.

### [x] P0-04 Define connection budget

- **Status:** Done (2026-11-16)
- **Depends on:** —
- **Done when:** these operating limits are written into `docker-compose` comments in Phase 6 and accepted here.

Comments are in `docker-compose.yml` and `docker-compose.prod.yml`. `TENANT_CONN_MAX_AGE = 0` is set in settings for the later tenant aliases.

Starting limits:

- Tenant connections use `CONN_MAX_AGE = 0` so a worker does not keep one connection per customer.
- Postgres `max_connections` stays at the image default until more than about 30 active tenants are expected.
- PgBouncer is a later task, not part of the first cutover.
- Web can scale horizontally. Scheduler stays at exactly one replica (`docker-compose.yml` already documents why).

---

## Phase 1 — Control plane

### [x] P1-01 Add the `control` app

- **Status:** Done (2026-11-16)
- **Depends on:** P0-01
- **Files:** `control/models.py` (`control` is already installed from P0)
- **Done when:**
  - `control` models exist and are the only new tables intended for the control database.
  - No Horilla HR model is imported into `control`.

### [x] P1-02 Models: `Operator`, `Tenant`, `Domain`, `ProvisionJob`

- **Status:** Done (2026-11-16)
- **Depends on:** P1-01, P0-02, P0-03
- **Files:** `control/models.py`, `control/migrations/0001_initial.py`

`Tenant` fields:

- `name`, `slug` (unique), `status` (`provisioning`, `active`, `suspended`, `failed`, `deleting`)
- `db_name`, `db_user`, `db_host`, `db_port`, `db_password_encrypted`
- `plan`, `created_at`, `activated_at`

`Domain` fields:

- FK to `Tenant`, `host` (unique), `is_primary`, `verified`

`ProvisionJob` fields:

- FK to `Tenant`, `kind` (`create`, `migrate`, `backup`, `restore`, `suspend`, `delete`)
- `step`, `status` (`queued`, `running`, `succeeded`, `failed`)
- `error` (truncated, no secrets), `started_at`, `finished_at`

`Operator` fields:

- email (unique), password hash, `is_active`, `is_staff`
- This is not `AUTH_USER_MODEL`.

**Done when:** `migrate` on a scratch control database creates only these tables plus Django tables that Phase 2 explicitly allows in the control database.

`control.0001_initial` creates these four tables. While `HORILLA_MULTITENANT` is off they live in the current database. The control allow-list, used once the flag is on, is `control`, `contenttypes`, `auth`, `sessions`, and `django_apscheduler`. `horilla_auth` and `employee` are not on that list.

### [x] P1-03 Encrypt and decrypt the tenant DB password

- **Status:** Done (2026-11-16)
- **Depends on:** P1-02, P0-03
- **Files:** `control/crypto.py`
- **Done when:**
  - Round-trip test passes.
  - A missing `TENANT_DB_FERNET_KEY` raises at first use in production.
  - `__str__` on `Tenant` does not include the password or the ciphertext.

### [x] P1-04 Database router

- **Status:** Done (2026-11-16)
- **Depends on:** P1-01
- **Files:** `control/router.py`, `horilla/settings/base.py` (`DATABASE_ROUTERS`)

Behavior:

- App label `control` always uses `default`.
- Every other app uses the tenant alias set for this request or job.
- If no tenant alias is set, the router raises. It must not fall back to `default` for HR models.
- `allow_migrate` runs `control` only on `default`, and Horilla apps only on a tenant alias.

**Done when:** a test that queries `employee` models with no alias fails, and a test that migrates `control` does not create `Employee` in the control database.

Strict routing runs only when `HORILLA_MULTITENANT` is on. With the flag off the router is a no-op, so the current single-tenant stack keeps using `default`. The alias holder is `control/context.py`; Phase 2 still wraps it around each request.

### [x] P1-05 Management command `migrate_tenants`

- **Status:** Done (2026-11-16)
- **Depends on:** P1-02, P1-04
- **Files:** `control/management/commands/migrate_tenants.py`
- **Done when:**
  - The command loads every `Tenant` with status `active`, registers the alias, and runs `migrate` on that alias.
  - One failure is recorded on a `ProvisionJob` and the command continues to the next tenant, then exits non-zero if any tenant failed.
  - It refuses to migrate a `suspended` tenant unless `--include-suspended` is passed.

### [x] P1-06 Split startup migrate

- **Status:** Done (2026-11-16)
- **Depends on:** P1-05
- **Files:** `docker/entrypoint.sh`
- **Done when:**
  - Web startup runs `migrate` for the control database, then `migrate_tenants`.
  - Scheduler still sets `HORILLA_SKIP_RELEASE_TASKS=1` and does not migrate.
  - A second web replica cannot race the first: document the single-migrator rule next to the existing scheduler comment in `docker-compose.yml`.

---

## Phase 2 — Request routing

### [x] P2-01 Thread-local or context-var for the active database alias

- **Status:** Done (2026-11-16)
- **Depends on:** P1-04
- **Files:** `control/context.py` (alias get/activate/clear landed in P1; this task still adds the request `finally` and the two-request test)
- **Done when:**
  - `activate(alias)` / `clear()` work, and `clear()` runs in a `finally` so a request cannot leak an alias into the next request on the same thread.
  - Tests cover two sequential requests on different aliases.

### [x] P2-02 Register a tenant connection lazily

- **Status:** Done (2026-11-16)
- **Depends on:** P2-01, P1-03
- **Files:** `control/db.py` (`ensure_tenant_connection` landed in P1; this task still proves first use from a request)

Register `connections.databases["tenant_<slug>"]` on first use with:

- `ENGINE` `django.db.backends.postgresql`
- `NAME`, `USER`, `PASSWORD`, `HOST`, `PORT` from the `Tenant` row
- `CONN_MAX_AGE = 0`
- `CONN_HEALTH_CHECKS = True`
- `OPTIONS.connect_timeout = 5`

**Done when:** the alias appears only after a request for that host, the password in the alias dict is the decrypted password, and settings.py does not list tenant databases.

### [x] P2-03 `TenantMiddleware`

- **Status:** Done (2026-11-16)
- **Depends on:** P2-02
- **Files:** `control/middleware.py`, `horilla/settings/base.py`

Order: this middleware is the first entry in `MIDDLEWARE`, before `SecurityMiddleware` is acceptable only if host parsing does not need it. Preferred order: after `SecurityMiddleware`, before `SessionMiddleware`, and before `base.middleware.CompanyMiddleware`.

Behavior:

- Dashboard host → mark the request as control-plane, do not open a tenant database.
- Other host → load `Domain` where `host` matches and `verified=True`.
- Unknown host → 404.
- Tenant `suspended` or `failed` or `provisioning` → 403 with a short message and no tenant data.
- Tenant `active` → `activate` the alias.
- `finally` clears the alias and closes that connection.

**Done when:** an unknown `Host` cannot read the control database’s operator list and cannot read another tenant’s employees.

### [x] P2-04 Host-based URL conf

- **Status:** Done (2026-11-16)
- **Depends on:** P2-03
- **Files:** `control/urls.py`, `horilla/urls.py` or a small root splitter

Behavior:

- Dashboard host includes `control.urls` only.
- Tenant host includes the existing Horilla `urlpatterns`.
- `/health/` stays available on every host and does not query a tenant database.
- `/ready/` checks the control database and Redis. It reports tenant-migration failures from the latest `ProvisionJob` without connecting to every tenant on each probe.

**Done when:** `manage.<platform-domain>/employee/` is 404, and `<slug>.<platform-domain>/control/` (dashboard paths) is 404.

### [x] P2-05 Cookie and CSRF isolation

- **Status:** Done (2026-11-16)
- **Depends on:** P0-01, P2-03
- **Files:** `horilla/settings/base.py`, `horilla/settings/security.py`
- **Done when:**
  - `SESSION_COOKIE_DOMAIN` and `CSRF_COOKIE_DOMAIN` are unset (`None`).
  - A session cookie issued on tenant A is not presented to tenant B (test in Phase 7).
  - `CSRF_TRUSTED_ORIGINS` can be extended when a custom domain is verified. Until custom domains exist, the wildcard platform origin is documented.

### [x] P2-06 `ALLOWED_HOSTS` for subdomains

- **Status:** Done (2026-11-16)
- **Depends on:** P0-01
- **Files:** `horilla/settings/base.py`, `.env` examples
- **Done when:** `. <platform-domain>` is accepted, the dashboard host is accepted, and a host that is not a verified `Domain` still dies in `TenantMiddleware` even if Django allowed the host header.

### [x] P2-07 Company middleware runs only after a tenant database is active

- **Status:** Done (2026-11-16)
- **Depends on:** P2-03
- **Files:** `base/middleware.py` (only if a guard is required), `horilla/settings/base.py` (`MIDDLEWARE` order)
- **Done when:**
  - `CompanyMiddleware` is unchanged in behavior for an active tenant.
  - A request with no tenant alias never reaches company lookup.
  - Existing company tests still pass when the test harness opens a single tenant database.

---

## Phase 3 — Provisioning engine

Provisioning runs in the scheduler process (or a dedicated `python manage.py run_provisioner` in that same single replica). The dashboard request only inserts a `ProvisionJob`. It does not call `CREATE DATABASE`.

### [x] P3-01 Control role can create databases

- **Status:** Done (2026-11-16)
- **Depends on:** P0-02
- **Files:** `docker/postgres/init-control.sql` (new), `docker-compose.yml`, `docker-compose.prod.yml`
- **Done when:**
  - The control login can `CREATE ROLE` and `CREATE DATABASE`.
  - The control login is not used as the Django connection for tenant queries.
  - App startup still waits on Postgres via `docker/entrypoint.sh`.

### [x] P3-02 SQL steps for a new tenant

- **Status:** Done (2026-11-16)
- **Depends on:** P3-01, P1-03
- **Files:** `control/provisioning.py`

Sequence, each step recorded on `ProvisionJob.step`:

1. Validate slug and reserved names.
2. `CREATE ROLE tenant_<slug> LOGIN PASSWORD '...'`.
3. `CREATE DATABASE tenant_<slug> OWNER tenant_<slug>`.
4. `REVOKE ALL ON DATABASE tenant_<slug> FROM PUBLIC`.
5. `GRANT CONNECT ON DATABASE tenant_<slug> TO tenant_<slug>`.
6. `REVOKE CONNECT` on that database from every other `tenant_*` role.
7. Store the encrypted password and the connection fields on `Tenant`.

**Done when:** a second tenant role cannot `psql` into the first tenant’s database.

### [x] P3-03 Migrate and seed inside the new database

- **Status:** Done (2026-11-16)
- **Depends on:** P3-02, P1-05
- **Files:** `control/provisioning.py`
- **Done when:**
  - `migrate` runs on the new alias before status becomes `active`.
  - The first `HorillaUser` is created from the job payload (admin name, email, temporary password).
  - The minimum `Company` row your current install expects is created in that same database.
  - Failure sets `Tenant.status = failed` and does not insert a usable primary `Domain`.

### [x] P3-04 Activate the hostname

- **Status:** Done (2026-11-16)
- **Depends on:** P3-03
- **Files:** `control/provisioning.py`
- **Done when:**
  - Primary `Domain` is `<slug>.<platform-domain>`, `is_primary=True`, `verified=True`.
  - `Tenant.status` becomes `active` only after migrate and seed succeed.
  - A request to that host reaches Horilla login and sees only the seeded company.

### [x] P3-05 Provisioner loop

- **Status:** Done (2026-11-16)
- **Depends on:** P3-04
- **Files:** `control/management/commands/run_provisioner.py` or an extra job inside `base/management/commands/run_scheduler.py`
- **Done when:**
  - Queued jobs run one at a time.
  - A crashed worker leaves the job `running` with `started_at` set; a restart reclaims jobs older than 30 minutes by marking them `failed`.
  - Two provisioners cannot run: the process lives in the single scheduler replica.

### [x] P3-06 Suspend and resume

- **Status:** Done (2026-11-16)
- **Depends on:** P2-03, P3-05
- **Files:** `control/provisioning.py`
- **Done when:**
  - Suspend sets `suspended` and keeps the database.
  - The host then returns 403.
  - Resume sets `active` without re-running `CREATE DATABASE`.

### [x] P3-07 Delete

- **Status:** Done (2026-11-16). P5-05 replaced the stub with `pg_dump`. A failed dump still refuses to drop the database.
- **Depends on:** P3-05, P5-05
- **Files:** `control/provisioning.py`
- **Done when:**
  - Delete requires the job payload to contain the exact slug.
  - A dump is taken first (P5-05).
  - Then `DROP DATABASE` and `DROP ROLE`, domain rows are removed, and status ends `deleted` or the row is removed. Decision: keep the row with status `deleted` and `deleted_at`. `dump_tenant` fails closed until P5-05 replaces it with `pg_dump`.
  - The hostname 404s afterwards.

### [x] P3-08 Retry from the last successful step

- **Status:** Done (2026-11-16)
- **Depends on:** P3-05
- **Files:** `control/provisioning.py`
- **Done when:** a tenant left in `failed` after `CREATE DATABASE` can be retried without a second `CREATE DATABASE` error, and the job log shows the resumed step.

---

## Phase 4 — Operator dashboard

The dashboard is server-rendered Django, on the management host only, using `control.Operator` sessions. It does not reuse Horilla employee templates for authorization.

### [x] P4-01 Operator login and logout

- **Status:** Done (2026-11-16). Session cookie name is `control_sessionid`.
- **Depends on:** P2-04, P1-02
- **Files:** `control/auth.py`, `control/views.py`, `control/templates/control/login.html`
- **Done when:**
  - Login checks `Operator` in the control database only.
  - Inactive operators cannot log in.
  - The session cookie name is distinct from the Horilla session cookie (proposed: `control_sessionid`) so a tenant session and an operator session cannot be confused.
  - Logout clears that cookie.

### [x] P4-02 Tenant list

- **Status:** Done (2026-11-16)
- **Depends on:** P4-01
- **Files:** `control/views.py`, `control/templates/control/tenant_list.html`
- **Done when:** the page lists name, slug, primary host, status, last job result, last backup time. It does not query tenant databases for employee counts on first load (that can be a later column fed by a job).

### [x] P4-03 Create-tenant form

- **Status:** Done (2026-11-16)
- **Depends on:** P4-02, P3-05
- **Files:** `control/forms.py`, `control/templates/control/tenant_form.html`
- **Fields:** company name, slug, admin name, admin email, temporary password, plan.
- **Done when:**
  - Submit inserts `Tenant(status=provisioning)` and `ProvisionJob(kind=create, status=queued)` and redirects to the detail page.
  - The request returns before `CREATE DATABASE` finishes.
  - Duplicate slug shows a form error.

### [x] P4-04 Tenant detail and job log

- **Status:** Done (2026-11-16). Backup, migrate, and restore jobs stay queued until phase 5 claims them.
- **Depends on:** P4-03
- **Files:** `control/templates/control/tenant_detail.html`
- **Done when:** the page shows domains, status, and every `ProvisionJob` step and error. Actions: suspend, resume, backup now, migrate, delete. Each action inserts a job; it does not perform the SQL inline.

### [x] P4-05 Delete confirmation

- **Status:** Done (2026-11-16)
- **Depends on:** P4-04, P3-07
- **Done when:** the operator must type the slug. A mismatched slug does not enqueue `delete`.

### [x] P4-06 Operator management

- **Status:** Done (2026-11-16)
- **Depends on:** P4-01
- **Files:** `control/views.py`, `control/templates/control/operators.html`
- **Done when:** a staff operator can create and deactivate another operator. The last active staff operator cannot deactivate themselves.

### [ ] P4-07 Custom-domain screen (milestone 2)

- **Status:** Not started. Left open: nginx for a custom domain is P6-04, which is not done. Subdomains from P4-04 are enough until then.
- **Depends on:** P4-04, P6-04
- **Done when:**
  - The form adds an unverified `Domain`.
  - The page shows the CNAME target and a verification token.
  - The host is attached in nginx and `verified=True` only after the check succeeds.
  - This task can stay open for the first production cutover. Subdomains are enough for milestone 1.

### [x] P4-08 Audit the dashboard itself

- **Status:** Done (2026-11-16). Rows live in `OperatorAudit`. The detail text is redacted and the page does not render job payloads.
- **Depends on:** P4-04
- **Files:** `control/models.py` (small `OperatorAudit` model or structured logs)
- **Done when:** create, suspend, resume, backup, restore, delete, and operator changes write who did it, when, and which slug. Passwords are not in the audit row.

---

## Phase 5 — Runtime isolation

### [x] P5-01 Cache keys include the tenant slug

- **Status:** Done (2026-11-16). `horilla.cache.tenant_cache_key`. Flag off keeps `horilla:<version>:<key>`.
- **Depends on:** P2-01
- **Files:** `horilla/settings/base.py`, `horilla/cache.py`, `horilla/isolation.py`, `control/middleware.py`
- **Done when:**
  - The Redis prefix is `horilla:<slug>:` for tenant requests.
  - A cache read or write with no tenant alias raises.
  - The same logical key in two tenants returns two values (Phase 7 can prove Redis; the key function is covered here).
  - Control-plane pages either skip the shared cache or use the prefix `horilla:control:`.

### [x] P5-02 Media paths include the tenant slug

- **Status:** Done (2026-11-16). Existing files are still copied at P8-03.
- **Depends on:** P2-01
- **Files:** `horilla/models.py` `upload_path`, `base/views.py` `protected_media`
- **Done when:**
  - New files land in `media/<slug>/...`.
  - A download checks that the relative path starts with the active slug before sending the file.
  - Existing single-tenant files are copied during cutover (P8-03).

### [x] P5-03 Scheduler loops active tenants

- **Status:** Done (2026-11-16). Policy: log the exception with the slug and continue to the next tenant.
- **Depends on:** P2-02, P1-02
- **Files:** `base/management/commands/run_scheduler.py`, `horilla/scheduling.py`, `control/scheduler.py`, `pg_backup/scheduler.py`
- **Done when:**
  - `DjangoJobStore` uses the control database.
  - Every job that touches HR tables iterates `Tenant.objects.filter(status="active")`, activates that alias, runs, and clears the alias in `finally`.
  - A job body that finds no alias aborts before a query.
  - One tenant’s exception is logged with the slug and does not skip the remaining tenants more than once for that tick. Record the actual policy in the progress log when implementing (proposed: log and continue).
  - Scheduler replica count stays 1.

### [x] P5-04 Management commands that assume one database

- **Status:** Done (2026-11-16). `--slug` is required only while `HORILLA_MULTITENANT` is on.
- **Depends on:** P5-03
- **Files:** `horilla/tenant_command.py`, HR commands under `*/management/commands/`
- **Done when:** a short inventory is appended to this task listing each command as `control-only`, `per-tenant`, or `unsafe`. Unsafe commands gain a required `--slug` and refuse to run without it.

Inventory:

- **control-only** (no `--slug`): `control.provision_tenant`, `control.migrate_tenants`, `control.run_provisioner`, `base.run_scheduler`. `migrate_tenants` and the provisioner already choose the database themselves.
- **per-tenant loop** (not a command): `horilla.scheduling.run_registered_job` for jobs with `per_tenant=True`. The provisioner and the nightly backup cron are `per_tenant=False`; the cron enqueues one backup job per active tenant and the provisioner runs `pg_dump`.
- **unsafe** (now `TenantSlugMixin`): `attendance.create_summary_fixtures`, `base.audit_perms`, `base.createhorillauser`, `base.create_branch_demo_fixtures`, `base.demo_data_inventory`, `base.horilladumpdata`, `base.load_demo_data`, `base.seed_dashboard_demo_data`, `base.trigger_save`, `dynamic_fields.add_field`, `dynamic_fields.delete_field`, `employee.import_ldap_users`, `helpdesk.create_faqs`, `horilla_auth.migrateusers`, `horilla_ldap.import_ldap_users`, `horilla_ldap.import_users_to_ldap`, `horilla_theme.create_default_themes`, `payroll.backfill_component_sequence`, `payroll.check_structure_invariants`, `payroll.create_payroll_fixtures`, `payroll.create_precise_payroll_fixtures`, `payroll.normalise_component_basis`, `payroll.payroll_snapshot`, `payroll.report_lop_deduction_mode`, `payroll.seed_tax_packs`, `payroll.sync_system_components`, `report.run_report_subscriptions`, `report.seed_standard_report_templates`.

### [x] P5-05 Per-tenant backup

- **Status:** Done (2026-11-16). The worker now claims backup, migrate, and restore jobs. `postgresql-client` is in the Dockerfile and is available after the next image build.
- **Depends on:** P3-02
- **Files:** `control/backup.py`, `control/provisioning.py`, `pg_backup/scheduler.py`, `horilla_backup/scheduler.py`, `Dockerfile`
- **Done when:**
  - Backup runs `pg_dump` against `tenant_<slug>` using that tenant’s database name, not `settings.DATABASES["default"]`.
  - Output path is `backups/<slug>/<timestamp>.dump`.
  - The dashboard “backup now” action enqueues this and the nightly scheduler runs it for every active tenant.
  - Dump files are not world-readable in the container.

### [x] P5-06 Per-tenant restore

- **Status:** Done (2026-11-16). A failed `pg_restore` leaves the tenant suspended.
- **Depends on:** P5-05, P3-06
- **Done when:**
  - Restore suspends the tenant first.
  - It loads the chosen dump into that same database.
  - It sets the tenant `active` only after `pg_restore` exits 0.
  - It cannot be pointed at a different slug than the dump’s folder.

### [x] P5-07 JWT and API stay inside the tenant database

- **Status:** Done (2026-11-16). The `tenant_slug` claim is checked before the user lookup. Flag off does not require the claim.
- **Depends on:** P2-03
- **Files:** `horilla_api/authentication.py`, `horilla_api/api_views/auth/views.py`
- **Done when:**
  - Token lookup uses the database selected from `Host` before the token is trusted.
  - A token minted on tenant A is rejected on tenant B’s host.
  - Company context is still applied after authentication, inside that database only.

---

## Phase 6 — Deploy and hosts

### [x] P6-01 Compose uses a control `DATABASE_URL`

- **Status:** Done (2026-11-16). Dev web and scheduler share one YAML anchor. Production compose and Django both refuse an empty `DATABASE_URL`.
- **Depends on:** P3-01
- **Files:** `docker-compose.yml`, `docker-compose.prod.yml`, `docker-compose.coolify.yml`, `.env.docker`, `.env.coolify.example`, `horilla/settings/security.py`
- **Done when:** web and scheduler share the control URL, tenant URLs are not in the environment, and production still refuses to start when `DATABASE_URL` is empty.

### [x] P6-02 Postgres `max_connections` note and healthcheck

- **Status:** Done (2026-11-16). The probe uses `POSTGRES_DB`, which is the control database.
- **Depends on:** P0-04, P6-01
- **Files:** `docker-compose.yml` (`db` service), `docker-compose.coolify.yml`
- **Done when:** the `db` healthcheck still checks the control database, and a comment states the connection budget from P0-04.

### [x] P6-03 Nginx wildcard server name

- **Status:** Done (2026-11-16). `HORILLA_PLATFORM_DOMAIN` defaults to `localhost`. The published prod port stays `127.0.0.1:8000`.
- **Depends on:** P0-01
- **Files:** `docker/nginx.conf`, `docker-compose.yml`, `docker-compose.prod.yml`
- **Done when:**
  - `manage.<platform-domain>` and `*.<platform-domain>` reach `web`.
  - Django is still bound to `127.0.0.1:8000` in `docker-compose.prod.yml`.
  - The Host header is forwarded unchanged.

### [ ] P6-04 TLS for the wildcard and for custom domains

- **Status:** Blocked. No platform domain is configured, so a certificate for `manage.<domain>` and `*.<domain>` cannot be issued. The names and the nginx example are in `docker/README.md` Step 4. Custom-domain certificates stay milestone 2, tied to P4-07.
- **Depends on:** P6-03
- **Done when:** milestone 1 has a certificate covering the dashboard host and `*.<platform-domain>`. Custom-domain certificates are documented as milestone 2, tied to P4-07.

### [x] P6-05 Production secrets checklist

- **Status:** Done (2026-11-16). Listed in `docker/README.md` section 13 and `.env.coolify.example`. `.env` stays gitignored. No real `TENANT_DB_FERNET_KEY` is in the repo.
- **Depends on:** P0-03, P6-01
- **Done when:** the deploy notes list `SECRET_KEY`, `DATABASE_URL` (control), Postgres superuser or control role password, `REDIS_PASSWORD`, and `TENANT_DB_FERNET_KEY`, and none of those values are committed.

### [x] P6-06 Single migrator on release

- **Status:** Done (2026-11-16). Scheduler `depends_on` web healthy. `HORILLA_SKIP_RELEASE_TASKS=1` still skips migrate there.
- **Depends on:** P1-06
- **Done when:** a release runs control migrate and `migrate_tenants` from one web container before the scheduler is considered healthy, matching the existing `HORILLA_SKIP_RELEASE_TASKS` split.

---

## Phase 7 — Isolation tests

These tests are the acceptance gate for the project. A phase is not done if the matching test is open.

### [x] P7-01 Two tenants, same email and employee number

- **Status:** Done (2026-11-17)
- **Depends on:** P3-04, P2-03
- **Done when:** both databases accept the same admin email and the same employee number, and each host’s login returns only its own user.

### [x] P7-02 Object id from the other tenant

- **Status:** Done (2026-11-17)
- **Depends on:** P7-01
- **Done when:** an authenticated request on tenant A for an employee primary key that exists only in tenant B returns 404.

### [x] P7-03 Session cookie is not portable

- **Status:** Done (2026-11-17)
- **Depends on:** P2-05, P7-01
- **Done when:** tenant A’s session cookie, sent to tenant B’s host, is an anonymous user.

### [x] P7-04 Cache and media cannot cross

- **Status:** Done (2026-11-17)
- **Depends on:** P5-01, P5-02
- **Done when:** the same cache key written in both tenants reads back different values, and a file path under `media/<other-slug>/` is refused on this host.

### [x] P7-05 Scheduler without an alias aborts

- **Status:** Done (2026-11-17)
- **Depends on:** P5-03
- **Done when:** invoking a tenant job function with no active alias raises before any HR query. A job run with two active tenants writes only into the alias it activated.

### [x] P7-06 Direct database login cannot cross

- **Status:** Done (2026-11-17)
- **Depends on:** P3-02
- **Done when:** an integration test (or a documented `psql` check in CI) shows `tenant_a` cannot connect to `tenant_b`.

Also keep the existing company tests (`base/tests/test_multi_tenancy.py`) green inside a single tenant database. Those tests prove company switching, not customer isolation. Do not treat them as a substitute for P7-01 through P7-06.

---

## Phase 8 — Cutover of the current install

Do this only after Phase 7 is green on a staging stack.

### [x] P8-01 Inventory the live database

- **Status:** Done (2026-11-17). Local Compose only. `horilla_db` was not renamed or overwritten.
- **Depends on:** P7-06
- **Done when:** the current database name, owner, and media root are written here, and a full `pg_dump` is stored outside the repo.

| Item | Value |
| --- | --- |
| Current database | `horilla_db` (owner `horilla_user`, about 41 MB). Also present: `tenant_cldv`, `tenant_acme`. |
| Current role | `horilla_user` (`CREATEDB`, `CREATEROLE`). Tenant logins `tenant_cldv` and `tenant_acme` are not superusers. |
| Media root | Named volume mounted at `/app/media`. |
| Dump path | `D:\docker\horilla-cutover\horilla_db-2026-11-17.dump` (custom format, 2,256,532 bytes). Outside the repo. |
| Dump taken at | 2026-11-17 13:30 local |

The served customer database is the existing `tenant_cldv` (Coldverse, badge `CLDV002`), not a copy of `horilla_db` (badge `PEP0001`). `horilla_db` stays as the pre-cutover database and the rollback source.

### [x] P8-02 Create the control database beside the live data

- **Status:** Done (2026-11-17). `horilla_control` is migrated with `HORILLA_MULTITENANT` on, so it has `control_tenant` and `control_operator` and does not have `employee_employee` or `base_company`.
- **Depends on:** P8-01, P6-01
- **Done when:** `horilla_control` exists, operators can log in to an empty dashboard, and the live HR database is still served unchanged until P8-04.

Control rows were copied from `horilla_db` (operators 2, tenants 2, domains 2, provision jobs 14, audit rows 13). Password hashes were copied and not reset. `manage.localhost/control/login/` returns 200. The active operator is `jagdish.parmar@coldverse.in`. `horilla_db` was still the live database until P8-04.

### [x] P8-03 Move the live database under a tenant role

- **Status:** Done (2026-11-17) by keeping the existing tenant databases. `horilla_db` was not renamed into `tenant_cldv`.
- **Depends on:** P8-02, P5-02
- **Done when:**
  - The existing database is renamed or dumped into `tenant_<slug>` owned by `tenant_<slug>`. Here the already-provisioned `tenant_cldv` and `tenant_acme` are the customer databases. Each is owned by its own role.
  - `CONNECT` is revoked from `PUBLIC` and from other tenant roles. `tenant_cldv` grants connect only to `tenant_cldv`. A login as `tenant_acme` to `tenant_cldv` is denied, and the error does not contain the password.
  - Media files are under `media/<slug>/` and existing URLs still resolve for that host. 130 files were copied to `/app/media/cldv/`; the originals were left in place. `tenant_cldv` has no stored `employee_profile` path. A file under `/media/cldv/...` is found (private files redirect to login). The same file requested as `/media/acme/...` is 404. An unprefixed `/media/employee/...` path is 404, which is the P5-02 slug check.
  - A `Tenant` and primary `Domain` row point at it with status `active`. `cldv` → `tenant_cldv` / `cldv.localhost`, and `acme` → `tenant_acme` / `acme.localhost`. Both domains are primary and verified.

### [x] P8-04 Switch traffic

- **Status:** Done (2026-11-17) for this local install. The gitignored `docker-compose.override.yml` points web and scheduler `DATABASE_URL` at `horilla_control` and sets `HORILLA_LEGACY_HOST_REDIRECT=cldv.localhost`. Committed `docker-compose.yml` still names `horilla_db`.
- **Depends on:** P8-03, P6-03
- **Done when:** the customer host hits the tenant database, the old bare host redirects to that customer host or to the dashboard, and `/health/` stays green.

Checked on port 8000 and through nginx on port 80: `/health/` and `/ready/` are 200 on `localhost` and `127.0.0.1`. `/login/` on those hosts is 302 to `http://cldv.localhost/login/` (port 8000 is preserved when the request used it). `cldv.localhost` and `acme.localhost` login pages are 200. `manage.localhost/control/login/` is 200. Web is healthy and the scheduler is running against `horilla_control`.

### [x] P8-05 Rollback drill

- **Status:** Written (2026-11-17). This is the local drill. It has not been signed off for production. The person who runs a production cutover still has to read it on that day.
- **Depends on:** P8-04
- **Done when:** a written rollback lists how to point the app back at the pre-cutover dump, and that drill has been read by the person who will run the production cutover.

Flag name: `HORILLA_MULTITENANT`. After this local cutover it is on. Turn it off only for rollback.

Rollback for this install:

1. Stop web and scheduler.
2. In the gitignored `docker-compose.override.yml`, point `DATABASE_URL` back at `horilla_db`, remove `HORILLA_LEGACY_HOST_REDIRECT`, and set `HORILLA_MULTITENANT` off.
3. Start web and scheduler. The bare host then serves `horilla_db` again, with no redirect.
4. Restore `D:\docker\horilla-cutover\horilla_db-2026-11-17.dump` only if `horilla_db` was changed. This cutover did not change it.
5. Do not drop `tenant_cldv`, `tenant_acme`, or `horilla_control`.

Do not commit `TENANT_DB_FERNET_KEY` or database passwords. The key stays in the gitignored override.

---

## Milestone cuts

**Milestone 1 — can sell to a second customer**

P0, P1, P2, P3-01 through P3-06, P4-01 through P4-06, P4-08, P5, P6-01 through P6-03, P6-05, P6-06, P7, P8.

Custom domains (P4-07, P6-04 beyond the wildcard) wait.

**Milestone 2 — custom domains and restore from the dashboard**

P3-07, P3-08, P4-07, P5-06, P6-04 for per-host certificates.

## Out of scope for this plan

- Schema-per-tenant and shared-table `tenant_id` designs.
- A second container or a second Postgres server per customer. A later tenant row may store a different `db_host` without an application rewrite; that hosting change is not scheduled here.
- Rewriting `HorillaCompanyManager` into a customer boundary.
- One mobile build per customer.
- Billing, invoicing, and plan enforcement beyond storing a `plan` string on `Tenant`.

## Implementation order (short)

1. P0 decisions, then P1 models and the router that fails closed.
2. P2 middleware and host split, with tests that an unknown host sees nothing.
3. P3 provisioning SQL and the background job.
4. P4 dashboard on top of jobs that already exist.
5. P5 cache, media, scheduler, backups.
6. P6 compose and nginx.
7. P7 full isolation suite.
8. P8 move the current database last.
