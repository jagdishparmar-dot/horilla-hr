# Control product redesign — implementation plan

Status: **Draft**
Owner: —
Last updated: 2026-11-18
Decision: reshape the operator dashboard toward the PeopleLedger Control screens, on the Django control app that already exists. Jobs stay queued. This document is the tracker.

PeopleLedger (`D:\docker\peopleledger-control`) is a browser demo. Its tenants, invoices, and audit rows live in `localStorage`. Horilla already persists tenants, domains, jobs, and operator audit in `horilla_control`. Copy the operator workflows. Do not copy the demo store.

Task ids use the **C** prefix so they do not collide with `P0`–`P8` in `2026-11-16-database-per-tenant-implementation.md`.

## How to use this doc

1. Work phases in order. A task lists the earlier tasks it depends on.
2. Do not start a task whose dependencies are still open.
3. When a task is finished, check the box, set **Status** to `Done`, add the date, and append one line to the progress log.
4. If a task is blocked, set **Status** to `Blocked` and write the blocker in the progress log.
5. A phase that changes a page is not done until that page is exercised in the browser on the management host: load, submit, and confirm the job or record that the button creates.

Status values: `Not started` · `In progress` · `Blocked` · `Done`

## Progress

| Phase | Tasks | Done |
| --- | ---: | ---: |
| 0. Shell | 5 | 5 |
| 1. Plans and subscription | 7 | 7 |
| 2. Quotas and modules | 5 | 5 |
| 3. Directory and trial | 6 | 6 |
| 4. Billing ledger | 5 | 5 |
| 5. Health and audit | 3 | 3 |
| 6. Setup access | 2 | 2 |
| **Total** | **33** | **33** |

### Progress log

| Date | Task | Note |
| --- | --- | --- |
| 2026-11-17 | — | Draft from the PeopleLedger review. No redesign code yet. |
| 2026-11-17 | — | Prices locked in INR for India. The PeopleLedger USD list is multiplied by 100 and stored as whole rupees. |
| 2026-11-17 | C0 | Shell, KPI strip, status tabs, and grouped tenant detail (`Overview`, `Operations`, `Access`) landed. Phase-2, Phase-4, and `test_redesign_shell` (20 tests) passed. Verified on `manage.localhost` and `acme.localhost`; queued backup job #16 succeeded. |
| 2026-11-17 | C1 | INR catalog, quote, subscription fields, and the plans page landed. Existing labels `free` on `acme` and `cldv` mapped to Unassigned. The string plan column was removed. |
| 2026-11-17 | C2 | Seat and storage limits, module flags, overview save form, and `snapshot_tenant_usage` landed. Saving limits writes an audit line and does not queue a job. `acme` seat limit is 40 after the browser check. |
| 2026-11-18 | C3 | Trial status, convert, suspension reason, company contact fields, and directory filters landed. A trial is routable and included in the scheduler loop. The trial nav count is hidden at zero. |
| 2026-11-18 | C4 | Invoice ledger, issue on convert and subscription change, past due, mark paid, void, and the billing page with CSV. A past-due tenant stays routable. The billing nav count is open plus past-due invoices. |
| 2026-11-18 | C5 | Tenant health checks, audit categories with backfill, and the platform audit page. A missing backup fails that line only. The category filter hides other rows, and a row links to the tenant when the slug still exists. |
| 2026-11-18 | C6 | Access section shows Pending, Accepted, or Not issued with the admin name and email. Regenerating a pending setup password shows the new value once, retires the old one, and writes a security audit. |

## Locked decisions

- **Stay on server-rendered Django.** Templates under `control/templates/control/`. No second Next.js app.
- **Jobs stay jobs.** Create, suspend, resume, backup, migrate, restore, and delete still insert a `ProvisionJob` and return. The request does not run `CREATE DATABASE`, `pg_dump`, or `DROP DATABASE`.
- **List pages do not open tenant databases.** The directory reads the control database only. Usage numbers are a stored snapshot, refreshed by a command or by opening one tenant.
- **Money is a quote, not a charge.** Prices are integer Indian rupees. There is no payment provider, webhook, or card form in this plan. Amounts are exclusive of GST. This plan does not calculate GST.
- **Plans are rows, not a free-text label.** `Tenant.plan` (the current string) is replaced by a foreign key after a data migration. Unknown labels become plan `unassigned`.
- **Add-ons change the quote.** They do not install or remove Django apps.
- **Module flags are stored.** `employee_records`, `payroll_engine`, and `performance_reviews` default to on. Turning one off does not hide Horilla menus in this plan. Enforcement inside a tenant app is a later plan.
- **Seat and storage limits are stored and edited.** The control app refuses a limit below the last snapshot. It does not yet block creating an employee inside Horilla.
- **Trial is a status.** `trialing` for 14 days from activation. Convert sets `active`. It does not take a payment.
- **Past due is a status.** An operator marks an invoice past due. Marking the last open or past-due invoice paid sets the tenant back to `active` when the tenant was `past_due`.
- **Suspension keeps a note.** The suspend form requires a short reason. Resume clears it.
- **Admin invite is the setup password.** Pending means `setup_password_encrypted` is set. Accepted means it was cleared after Initialize Database. This plan can regenerate that password. It does not send email.
- **One Postgres host.** Region labels from the prototype are not built.
- **SSO and API keys are not in this plan.**
- **Operators stay.** `control.Operator`, cookie `control_sessionid`, and the operators page stay as they are.
- **Do not drop `acme` or `cldv`** while building this. Tests use their own slugs.

## What already exists and must keep working

| Operator action | Where it lives now |
| --- | --- |
| Login and logout | `control/auth.py`, `control/views.py`, cookie `control_sessionid` |
| Tenant list, search, status filter | `control/templates/control/tenant_list.html` |
| Create tenant | `TenantCreateForm`: name, slug, free-text plan |
| Detail: domains, database identity, jobs, audit | `control/templates/control/tenant_detail.html` |
| Suspend, resume, backup, migrate, restore, delete | POST views in `control/urls.py`, worker in `control/provisioning.py` |
| Setup password | `control/setup_access.py`, cleared after first admin |
| Operator audit | `control/audit.py`, actions for the jobs above |

Statuses today: `provisioning`, `active`, `suspended`, `failed`, `deleting`, `deleted`.

## Out of this plan

- Payment provider, dunning email, tax, proration beyond a single new invoice for the new monthly quote.
- Per-tenant SSO (SAML, Google, Entra, magic link) and API key rotation.
- Data-residency regions and a second database host.
- Hiding Horilla modules when a flag is off.
- Blocking employee create when seats are full.
- Browser `localStorage`, reset-to-seed, and a JSON dump of the whole workspace.
- Rebuilding backup, migrate, restore, or delete.

---

## Phase 0 — Shell

The operator can move through the same four areas as the prototype. No new business rules. Existing POST actions still enqueue the same jobs.

### [x] C0-01 Navigation

- **Status:** Done (2026-11-17)
- **Depends on:** —
- **Files:** `control/templates/control/base.html`, `control/urls.py`, `control/views.py`, `control/templatetags/control_ui.py`

Add four destinations plus the existing operators link:

- Tenants (`control-home`)
- Plans (`control-plans`) — placeholder page until C1-04
- Billing (`control-billing`) — placeholder page until C4-04
- Audit (`control-audit`) — placeholder page until C5-03
- Operators (existing)

Show the tenant count on Tenants. Leave invoice and attention badges until C3 and C4 have data.

**Done when:** each destination renders for a logged-in operator, a logged-out request still redirects to login, and tenant hosts still do not serve these URLs.

### [x] C0-02 KPI strip

- **Status:** Done (2026-11-17)
- **Depends on:** C0-01
- **Files:** `control/views.py`, `control/templates/control/tenant_list.html`

Four figures from the control database only:

- Managed tenants, with active and provisioning counts
- Suspended count
- Failed jobs in the last 7 days
- Tenants whose newest backup job is missing or older than 7 days

Do not show revenue until C1 has a quote and C4 has invoices.

**Done when:** the figures match a queryset test, and the list query count does not grow with the number of tenant databases.

### [x] C0-03 Status tabs

- **Status:** Done (2026-11-17)
- **Depends on:** C0-02
- **Files:** `control/templates/control/tenant_list.html`, `control/views.py`

Replace the single status dropdown with tabs that show a count: All, Active, Provisioning, Suspended, Failed. Trialing and Past due tabs appear in C3 and C4 when those statuses exist. Keep the text search.

**Done when:** each tab filters the same rows the current query filters, and an empty tab states that no tenants match.

### [x] C0-04 Detail sections

- **Status:** Done (2026-11-17)
- **Depends on:** C0-01
- **Files:** `control/templates/control/tenant_detail.html`, `control/static/control/js/control.js`

Group the current page into three sections. Do not drop a field or a button.

- Overview: name, slug, status, plan label, primary host, database identity
- Operations: job table, backup, migrate, restore, suspend, resume, delete
- Access: setup-password state, domains, open-tenant link

**Done when:** every current action still posts to the same URL and still creates the same job kind. Phase-4 view tests stay green.

### [x] C0-05 Regression pass

- **Status:** Done (2026-11-17)
- **Depends on:** C0-02, C0-03, C0-04
- **Files:** `control/tests/test_phase4.py`, `control/tests/test_redesign_shell.py`
- **Done when:**
  - `test_phase4` passes.
  - A new test loads the list, each placeholder page, and a tenant detail page as an operator.
  - The management host is checked in the browser: list, open a tenant, queue a backup, confirm the job row appears as queued or succeeded.

---

## Phase 1 — Plans and subscription

The free-text plan becomes a catalog. Prices are quotes for the operator. Nothing is charged.

Catalog, stored as data so a later edit does not require a template change. The India list is the PeopleLedger USD amount multiplied by 100, stored as whole rupees. ₹800 is the Starter seat price because the prototype seat price is 8. This rate is locked in the seed. It is not a daily exchange rate.

| Plan | Per seat / month | Seat cap | Storage / seat |
| --- | ---: | --- | ---: |
| Starter | ₹800 | 100 | 2 GB |
| Growth | ₹1,400 | 1,000 | 5 GB |
| Enterprise | ₹2,200 | none | 15 GB |
| Unassigned | ₹0 | none | none |

Annual cadence stores a 20% discount on the quote. The billed amount for an annual term is `monthly_after_discount * 12`.

Add-ons, same ×100 rule:

| Id | Price |
| --- | --- |
| `multi_state_tax` | ₹18,000 flat |
| `calibration_360` | ₹300 per seat |
| `audit_vault` | ₹14,000 flat |
| `priority_sla` | ₹26,000 flat |

Display amounts with `en-IN` grouping and the rupee sign. Seed these rupee amounts in the migration or seed command.

### [x] C1-01 Plan and add-on models

- **Status:** Done (2026-11-17)
- **Depends on:** C0-05
- **Files:** `control/models.py`, `control/migrations/`
- **Done when:** `Plan` has code, name, monthly price in rupees, seat cap (null means none), storage GB per seat, and `is_active`. `Addon` has code, name, amount in rupees, and `per_seat` boolean. Both live only in the control database. Starter’s monthly price is 800.

### [x] C1-02 Seed the catalog

- **Status:** Done (2026-11-17)
- **Depends on:** C1-01
- **Files:** `control/management/commands/seed_plans.py` or a data migration
- **Done when:** running migrate on a fresh control database inserts the four plans and four add-ons, and running it again does not duplicate rows.

### [x] C1-03 Quote function

- **Status:** Done (2026-11-17)
- **Depends on:** C1-01
- **Files:** `control/pricing.py`, `control/tests/test_redesign_pricing.py`

`quote(plan, cadence, seats, addon_ids)` returns base monthly rupees, discount rupees, add-on rupees, total monthly rupees, and annual rupees.

**Done when:** Growth, 10 seats, annual, no add-ons equals 10 * 1400 * 0.8 = ₹11,200 monthly. A test covers the 20% discount and one flat add-on plus one per-seat add-on. Amounts are whole rupees.

### [x] C1-04 Plans page

- **Status:** Done (2026-11-17)
- **Depends on:** C1-02, C1-03, C0-01
- **Files:** `control/templates/control/plans.html`, `control/views.py`
- **Done when:** the page lists the three sellable plans, the add-ons, and a small quote form (plan, cadence, seats, add-ons) that redisplays the quote on POST. `unassigned` is omitted from the sellable list. Browser check: change cadence and see the total change.

### [x] C1-05 Subscription on the tenant

- **Status:** Done (2026-11-17)
- **Depends on:** C1-01
- **Files:** `control/models.py`, migration

Add `plan_fk` (nullable during the migration), `cadence` (`monthly` or `annual`, default `monthly`), and a through table for selected add-ons. Keep the old `plan` string until C1-06 deletes it.

**Done when:** a tenant can point at Growth, annual, and one add-on, and the control router still refuses to migrate these tables into a tenant database.

### [x] C1-06 Move existing plan labels

- **Status:** Done (2026-11-17)
- **Depends on:** C1-02, C1-05
- **Files:** data migration

Map `starter`, `growth`, `enterprise` case-insensitively onto those plans. Every other value, including blank, becomes `unassigned`. Then remove the string column.

**Done when:** a test with plans `Growth`, `standard`, and blank ends as Growth, Unassigned, Unassigned, and `acme` / `cldv` still exist.

### [x] C1-07 Create form uses the catalog

- **Status:** Done (2026-11-17)
- **Depends on:** C1-06
- **Files:** `control/forms.py`, `control/templates/control/tenant_form.html`, `control/provisioning.py`

Fields: company name, slug, plan (sellable plans only), cadence. Default seats to the plan cap when the cap exists, otherwise 25. Store that seat limit only after C2-01; until then keep it in the create payload and document it in the form help text if C2 is not merged yet.

Prefer one sectioned form over a multi-page wizard. Validation errors must stay on the same page.

**Done when:** submit still returns before `CREATE DATABASE`, the tenant row references the chosen plan, and an unknown plan code is rejected. Browser check: create a disposable slug on the local stack only if the operator intends to delete it afterward.

---

## Phase 2 — Quotas and modules

Limits are operator records. Usage is a snapshot so the directory stays on the control database.

### [x] C2-01 Quota fields

- **Status:** Done 2026-11-17
- **Depends on:** C1-05
- **Files:** `control/models.py`, migration

On `Tenant`: `seat_limit`, `storage_limit_gb`, `active_seats`, `used_storage_gb`, `usage_updated_at`. Limits are required once the row is active. Snapshots may be zero.

**Done when:** creating a tenant copies `seat_limit` from the form and `storage_limit_gb` from `seat_limit * plan.storage_gb_per_seat`.

### [x] C2-02 Module flags

- **Status:** Done 2026-11-17
- **Depends on:** C1-05
- **Files:** `control/models.py`, migration

Booleans `module_employee_records`, `module_payroll_engine`, `module_performance_reviews`, all default true.

**Done when:** the create form can turn a module off, the value is stored, and no Horilla app is uninstalled.

### [x] C2-03 Edit limits and modules

- **Status:** Done 2026-11-17
- **Depends on:** C2-01, C2-02, C0-04
- **Files:** `control/forms.py`, `control/views.py`, `control/templates/control/tenant_detail.html`, `control/audit.py`

Overview shows both usage bars and a save form. New audit actions: `quota_update`, `module_update`.

**Done when:** a POST updates the control row, writes an audit line with the operator and the before/after numbers, and does not enqueue a provision job. Browser check: save a higher seat limit and see it on reload.

### [x] C2-04 Usage snapshot

- **Status:** Done 2026-11-17
- **Depends on:** C2-01
- **Files:** `control/management/commands/snapshot_tenant_usage.py`

For one slug, or for every `active` and `trialing` tenant: register that tenant alias, count employee rows, measure that tenant’s media directory, write the snapshot, then clear the alias. One tenant failure is recorded on the command output and the command continues.

The tenant list must not call this.

**Done when:** a test with a fixture tenant writes `active_seats` from that tenant database, and a second tenant is unchanged when the first raises.

### [x] C2-05 Limits cannot drop below the snapshot

- **Status:** Done 2026-11-17
- **Depends on:** C2-03
- **Files:** `control/forms.py`, `control/tests/test_redesign_quotas.py`

Also reject a seat limit above `Plan.seat_cap` when the cap is not null.

**Done when:** a form test with `active_seats=10` rejects `seat_limit=9` and accepts `10`. The stored row is unchanged on rejection.

---

## Phase 3 — Directory, trial, and suspension note

### [x] C3-01 Trial status

- **Status:** Done 2026-11-18
- **Depends on:** C1-07
- **Files:** `control/models.py`, `control/provisioning.py`, migration

Add status `trialing` and `trial_ends_at`. The create form gains “Start as trial”. The create job sets `trialing` and `trial_ends_at = activated_at + 14 days` instead of `active`. A trial tenant is routable the same way an active tenant is. Suspend, backup, migrate, and delete still apply.

**Done when:** a create job with the flag ends `trialing`, a create without the flag still ends `active`, and the scheduler’s per-tenant loop includes `trialing`.

### [x] C3-02 Convert trial

- **Status:** Done 2026-11-18
- **Depends on:** C3-01
- **Files:** `control/views.py`, `control/templates/control/tenant_detail.html`, `control/audit.py`

A button on a `trialing` tenant sets `active`, clears `trial_ends_at`, and writes audit action `trial_convert`. No invoice until C4-02.

**Done when:** the button is absent for `active`, and a POST on an `active` tenant is rejected.

### [x] C3-03 Suspension note

- **Status:** Done 2026-11-18
- **Depends on:** C0-04
- **Files:** `control/models.py`, `control/forms.py`, `control/provisioning.py`

Add `suspension_reason`. Suspend requires 1–200 characters and stores the text on the tenant when the job succeeds. Resume clears it.

**Done when:** an empty reason fails the form before a job is queued, and a successful resume leaves the reason blank.

### [x] C3-04 Company profile fields

- **Status:** Done 2026-11-18
- **Depends on:** C1-07
- **Files:** `control/models.py`, `control/forms.py`, migration

Add `industry` (blank allowed), `admin_name`, and `admin_email`. These describe the customer contact. They do not create a `HorillaUser`. The create form collects them. Detail overview displays them.

**Done when:** the values round-trip through create, and the tenant database has no new user until someone completes Initialize Database.

### [x] C3-05 Directory filters

- **Status:** Done 2026-11-18
- **Depends on:** C0-03, C1-06, C3-01, C3-04
- **Files:** `control/templates/control/tenant_list.html`, `control/views.py`

Tabs include Trialing. Search matches name, slug, host, industry, admin name, and admin email. A plan filter limits the list to one plan code. Each row shows plan name, cadence, and module names. Seat and storage percents use the snapshot columns only.

**Done when:** a queryset test finds a tenant by admin email, the plan filter excludes other plans, and the list still does not connect to a tenant database.

### [x] C3-06 Attention count

- **Status:** Done 2026-11-18
- **Depends on:** C3-01, C0-01
- **Files:** `control/templates/control/base.html`

The Tenants nav shows how many tenants are `trialing`. Past-due joins this count in C4-03.

**Done when:** the count matches the tab count and is hidden at zero.

---

## Phase 4 — Billing ledger

Operators record invoices and their status. The app does not collect money.

Invoice statuses: `open`, `paid`, `past_due`, `void`.

### [x] C4-01 Invoice model

- **Status:** Done (2026-11-18)
- **Depends on:** C1-03, C2-01
- **Files:** `control/models.py`, migration

Fields: tenant FK, plan code, cadence, seat count, amount rupees, status, period label, issued date, due date, paid date, voided date. No card data. No secret. No GST columns.

**Done when:** the table exists only in the control database, and amount rupees matches `quote(...).total_monthly` for a monthly invoice.

### [x] C4-02 Issue an invoice

- **Status:** Done (2026-11-18)
- **Depends on:** C4-01, C3-02
- **Files:** `control/billing.py`, `control/views.py`, `control/audit.py`

Issue one `open` invoice, due in 14 days, when:

- a trial is converted
- an operator saves a new plan, cadence, or add-on set on an `active` or `past_due` tenant

Changing only quotas or modules does not issue an invoice. Audit action: `invoice_issue`.

**Done when:** convert creates one invoice, a second convert click does not create another, and a quota-only save creates none.

### [x] C4-03 Past due and mark paid

- **Status:** Done (2026-11-18)
- **Depends on:** C4-01
- **Files:** `control/views.py`, `control/models.py`

Add tenant status `past_due`. An operator action sets an `open` invoice to `past_due` and the tenant to `past_due`. The tenant host keeps routing; this status is a billing mark, not a suspend. Mark paid sets the invoice `paid`. If the tenant is `past_due` and no `open` or `past_due` invoice remains, set the tenant `active`.

**Done when:** tests cover one overdue invoice and two overdue invoices, and paying only one of two leaves the tenant `past_due`.

### [x] C4-04 Billing page and CSV

- **Status:** Done (2026-11-18)
- **Depends on:** C4-02, C4-03, C0-01
- **Files:** `control/templates/control/billing.html`, `control/views.py`

Show quote totals by plan for `active` and `past_due` tenants, the trialing list, and invoices with a status filter. Export the filtered invoices as CSV. The nav badge counts `open` plus `past_due` invoices.

**Done when:** CSV columns are invoice id, tenant slug, period, plan, seats, amount rupees, status, issued, due. Browser check: filter to paid and confirm open rows disappear. The amount column is a whole number of rupees.

### [x] C4-05 Void

- **Status:** Done (2026-11-18)
- **Depends on:** C4-03
- **Files:** `control/billing.py`, `control/audit.py`

Void is allowed for `open` and `past_due`. A voided invoice no longer counts toward the past-due rule in C4-03. Audit action: `invoice_void`.

**Done when:** voiding the only past-due invoice sets that tenant `active`, and a paid invoice cannot be voided.

---

## Phase 5 — Health and audit

Health is three real checks for the open tenant. The prototype’s SSO, payroll-worker, and storage-vault probes are not copied.

### [x] C5-01 Tenant health panel

- **Status:** Done (2026-11-18)
- **Depends on:** C0-04, C2-04
- **Files:** `control/health.py`, `control/views.py`, `control/templates/control/tenant_detail.html`

On the detail page, a button runs three checks for that slug only:

- control row can open a connection as the tenant role
- newest backup job succeeded, and its dump file is present
- newest migrate job succeeded, or the tenant is active and has no failed migrate

Each line stores status `healthy`, `degraded`, or `failed`, plus a short detail with no password and no connection string. Degraded backup means the newest success is older than 7 days. Degraded storage means the snapshot is at least 85% of the limit.

**Done when:** a test tenant with no backup is `failed` on that line, and the other two lines do not require a successful backup.

### [x] C5-02 Audit categories

- **Status:** Done (2026-11-18)
- **Depends on:** C2-03, C4-02
- **Files:** `control/models.py`, `control/audit.py`, migration

Add `category` on `OperatorAudit`: `provisioning`, `subscription`, `quota`, `security`, `billing`. Backfill existing rows as `provisioning`, except operator create/deactivate which are `security`. New actions from C2–C4 set the matching category.

**Done when:** a backfill test maps `backup` to `provisioning` and `invoice_issue` to `billing`.

### [x] C5-03 Audit page

- **Status:** Done (2026-11-18)
- **Depends on:** C5-02, C0-01
- **Files:** `control/templates/control/audit.html`, `control/views.py`

Platform-wide log, newest first, filter by category, link to the tenant when the slug still exists. The per-tenant audit list on the detail page stays.

**Done when:** the filter hides other categories, the page does not render `setup_password` or database passwords, and a browser check opens a tenant from a row.

---

## Phase 6 — Setup access

This is the prototype’s “resend invite”, using the password that already gates Initialize Database.

### [x] C6-01 Invite state

- **Status:** Done (2026-11-18)
- **Depends on:** C0-04, C3-04
- **Files:** `control/templates/control/tenant_detail.html`

Access section shows admin name, admin email, and one of:

- Pending, when `setup_password_encrypted` is set
- Accepted, when the tenant is `active` or `trialing` and the password has been cleared
- Not issued, otherwise

**Done when:** a template test covers all three branches and the password value is absent from the HTML.

### [x] C6-02 Regenerate setup password

- **Status:** Done (2026-11-18)
- **Depends on:** C6-01
- **Files:** `control/views.py`, `control/setup_access.py`, `control/audit.py`

Allowed only while the password is still set. Generate a new password, store it the same way create does, show it once on the next detail render, and audit `setup_password_reset` under category `security`.

**Done when:** a second person loading the page later does not see the password, the old password no longer matches, and the button is hidden after Initialize Database clears it.

---

## Suggested review order

Read the locked decisions first. If a decision changes, edit it here before the phase that implements it.

1. Phase 0 can start without product debate. It only rearranges the current dashboard.
2. Phase 1 sets the India price list in rupees. The seed amounts are already locked above. Change that table before C1-02 if the ×100 rate should be different.
3. Phases 2 and 3 are the tenant inspector the prototype shows.
4. Phase 4 is the first time the control database stores money. Confirm that a manual ledger is enough.
5. Phases 5 and 6 finish the operator loop without SSO or email.

## Browser checks that apply to every phase

Use the management host (`manage.localhost` locally). Sign in as an operator.

- The page that the phase names loads without a server error.
- Submit the form the phase adds. Confirm the control row or the queued job. Do not expect the HTTP request itself to dump or drop a database.
- Open the tenant host for `acme` or `cldv` and confirm the HR app still loads. This redesign does not change tenant routing.
- Leave `acme` and `cldv` in place. Create a disposable tenant only when the task says to, and delete it through the existing delete job after `pg_dump` is available in that environment.
