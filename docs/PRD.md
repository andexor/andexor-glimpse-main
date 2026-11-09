# Andexor Glimpse — Master PRD

Version 1.0 · 2026-11-09 · Author: Ed Jenkins (ed@andexor.net) · Source of truth for the Andexor Glimpse family of repositories

Andexor Glimpse is a system that creates systems. Ed enters a company name and the prospect's email address, and the system provisions, gates, delivers, and retires an isolated website preview (a glimpse) for that prospect, then collects the prospect's decision and comments.

## 1. Purpose

A glimpse is a preview of what a prospect's website could look like, offered to a business that has no website or has one that needs a modern look, better security, performance, accessibility, or AI-assisted buying. The name comes from the film [The Family Man](https://www.imdb.com/title/tt0218967/).

The system exists to make producing a glimpse cheap enough to offer to every qualified prospect. Given a company name and the prospect's email address (owner name and phone optional), it must:

1. Provision two private GitHub repositories and a fully isolated Cloudflare deployment for the glimpse, seeded with a minimal Hello World app.
2. Gate the glimpse so only the prospect can see it, and keep it out of search engines.
3. Let Ed replace the Hello World content with a real design as a manual step, then notify the prospect by email or SMS.
4. Give the prospect a portal to approve or decline and leave unlimited comments; notify Ed on every submission.
5. Expire access after 7 days, delete the private repos after 30 days, and let Ed revive, delete early, or re-create a glimpse at any time.
6. Record every glimpse, decision, comment, and scheduled event in Cloudflare D1, with each glimpse isolated from all others.

**Out of scope for v1:** the design content itself (manual), the real email/SMS delivery plumbing (stubbed), billing, and multi-user agency accounts (single operator).

## 2. Naming convention and repository map

**Standard for all Andexor multi-tier projects:** `andexor-<system>[-<component>]-<tier>`, where tier is `ui` for a front-end app and `api` for a back-end service. `ui`/`api` beats `fe`/`be` (opaque to outsiders) and `ui`/`server` (`api` says what the server exposes, and a future worker that is not an API can take `-worker` or `-jobs`). The `andexor-<system>-main` repo governs the family: master PRD, Spec Kit constitution, PlantUML diagrams, database schemas, API contracts, and shared decisions.

**Identifier casing rule (all Andexor projects):** every identifier the system creates — Universally Unique Identifiers (UUIDs), hexadecimal codes, glimpse IDs — is lowercase in every place it appears: database, logs, UIs, hostnames, Cloudflare resource names, and API calls. This follows RFC 4122, which emits UUIDs in lowercase, and gives one canonical form so no comparison ever depends on case folding. No prefixes are added to identifiers.

**CSS colour casing rule (all Andexor projects):** hexadecimal colour codes in CSS are uppercase (e.g. `#1A73E8`). Stylelint `color-hex-case` is set to `upper` to enforce it.

**Finite-value fields and the System Reference Table (SRT):** every field with a finite set of values (states, kinds, statuses, actions, actors, channels) holds an UPPERCASE code, and every database carries an `srt` table (`domain`, `code`, `label`, `description`, `sort_order`, `active`) that is the authoritative list of those codes. Triggers reject any write whose code is not active in `srt`, so adding a value is a migration, never a code edit. UIs read labels and ordering from `srt`. Glimpse states are `PROVISIONING`, `FAILED`, `DRAFT`, `PENDING`, `APPROVED`, `DECLINED`, `DELAYED`, `EXPIRED`, `DELETED`; decision actions are `APPROVED`, `DECLINED`, `DELAYED`.

Glimpse IDs are 20-character lowercase base32 strings generated from 100 random bits (e.g. `q7mx2k9pbd4ht6wz3nra`). Base32 is used instead of a UUID because the same value must serve as a DNS label, a repo-name segment, and a database name, and a UUID is longer and carries hyphens that read badly in hostnames.

| Repo | Visibility | Stack | Role |
| --- | --- | --- | --- |
| `andexor-glimpse-main` | Public | Docs, PlantUML, Spec Kit | Governing repo for the family |
| `andexor-glimpse-admin-ui` | Public | Next.js (CSR) | Ed's admin app: create, monitor, revive, delete glimpses |
| `andexor-glimpse-admin-api` | Public | FastAPI on Python Workers | Provisioning engine: GitHub, Cloudflare, D1, scheduling |
| `andexor-glimpse-portal-ui` | Public | Next.js (CSR) | Prospect portal: view status, approve/decline, comment |
| `andexor-glimpse-portal-api` | Public | FastAPI on Python Workers | Prospect-facing API with its own D1; sole owner of feedback; alerts Ed directly |
| `andexor-glimpse-<id>-ui` | Private (one per glimpse) | Next.js (CSR) | The glimpse site itself |
| `andexor-glimpse-<id>-api` | Private (one per glimpse) | FastAPI on Python Workers | Per-glimpse back end under /api/\* with its own D1 |

All repos live in the `andexor` GitHub organization, never under `ejenkins`. Cloudflare Worker, Pages project, and D1 database names reuse the repo name exactly.

**Hostnames:** one per tier: `admin.glimpse.andexor.net`, `portal.glimpse.andexor.net`, and `<id>.glimpse.andexor.net` for each glimpse. Each hostname carries two Worker Routes: `host/*` to the `-ui` Worker and `host/api/*` to the `-api` Worker, so a single Cloudflare Access application covers both the UI and its API. There are no separate `api.` hostnames. The earlier `sandbox.andexor.net` name is retired in favour of `glimpse`.

## 3. System components

Three tiers plus a governing repo. The admin and portal tiers are long-lived and deployed once; the glimpse tier is stamped out per prospect by the admin API.

| Tier | Component | Users | Responsibilities |
| --- | --- | --- | --- |
| Admin | `admin-ui` | Ed | Create glimpse from company name; dashboard of all glimpses with state and upcoming event dates; revive, delete, re-create; view comments and decisions; trigger prospect notification |
| Admin | `admin-api` | `admin-ui` only | Provisioning engine: create and configure GitHub repos, Cloudflare Workers, D1 databases, DNS, Access apps; schedule expiry/deletion; emit SSE progress; own the system D1 |
| Prospect | `portal-ui` | Prospects | See their glimpse link and expiry date; approve or decline; add comments |
| Prospect | `portal-api` | `portal-ui` only | Serve the signed-in prospect's glimpse record; append every approve, decline, and delay to decision\_log and store comments; alert Ed on each; call admin-api to extend; answer admin-api's on-demand feedback reads |
| Glimpse | `<id>-ui` | One prospect | The preview site; Hello World until Ed replaces it |
| Glimpse | `<id>-api` | `<id>-ui` only | Per-glimpse back end with its own D1; empty in Hello World, available for AI-assisted buying features in real designs |
| Governing | `andexor-glimpse-main` | Ed, Claude Code | Master PRD, child PRD index, Spec Kit constitution, PlantUML component/sequence/state diagrams |

The admin API is the only component with write credentials to GitHub and the Cloudflare account, and the only one bound to the system database. The portal API is bound only to the portal database. Per-glimpse APIs are bound only to their own database. The admin and portal APIs are independent systems with four narrow Service Binding methods between them (section 7), never a shared or replicated database.

Future back-end services (content generation, analytics, lead scoring) attach to the admin tier as `andexor-glimpse-<name>-api` and are called by `admin-api`; this PRD reserves no behaviour for them.

## 4. Platform and stack decisions

| Decision | Choice | Rationale / constraint |
| --- | --- | --- |
| Front-end framework | Latest Next.js, Client Side Rendering (CSR), Node via existing nvm | Full web apps; CSR keeps the Worker thin; matches `andexor-net-website` tooling. No Bun, no Docker unless a reason appears |
| Back-end framework | Latest FastAPI on Cloudflare Python Workers, uv-managed | Matches `andexor-net-website-contact-us`; Python Workers run FastAPI via the Pyodide runtime — package support must be verified per dependency (see Risks) |
| Hosting | Cloudflare for everything: Workers, Pages or Workers Assets for UIs, D1, DNS, Access | One account, one Application Programming Interface (API), one bill |
| Database | Cloudflare D1; one database per API: the system database owned by `admin-api`, the portal database owned by `portal-api`, and one database per glimpse. No database is shared between Workers | Least privilege by construction: each Worker can reach only its own data. Admin and portal are independent systems joined by four Service Binding methods: admin sends portal the glimpse record and fetches feedback on demand; portal reports extend and record\_decision (section 7) |
| Authentication | Cloudflare Access with email One-Time PIN (OTP) for admin UI, portal UI, and every glimpse | No passwords stored; policies are allow-lists of email addresses; Free plan covers 50 users, $7/user/month beyond |
| Requirements management | GitHub Spec Kit (`specify` CLI, `--integration claude`) in `andexor-glimpse-main` and in each generated glimpse repo pair | Constitution at the family level; `spec.md`/`plan.md`/`tasks.md` per child project |
| Robots | All system and glimpse hosts: `X-Robots-Tag: noindex, nofollow`, `robots.txt` disallow all, `<meta name="robots">`, no sitemap, `rel="nofollow"` on outbound links | Internal and prospect-only surfaces |
| Consent | Cookiebot, wired as in `andexor-net-website` | To be verified against CSR apps |
| Design system | FontAwesome, same Google Fonts, Andexor Network Design System for admin and portal UIs only | Glimpses carry the prospect's design, not Andexor's |
| Scheduling | Cloudflare Cron Triggers on `admin-api`; every scheduled event is also a row in D1 with its cron expression and next-run timestamp | Dates shown in UIs, expressions visible in the database, not hunted in the console |
| Tooling in Claude Code | GitHub MCP server + `gh` CLI; Cloudflare MCP server + `wrangler`; authenticated as Ed, verified with a read-only call before any write | Same tools the admin API will drive programmatically |
| Observability | Every Worker (system and glimpse) has Workers Logs, Workers Traces, and Workers Issues enabled in its Wrangler configuration; structured JSON logging via console.log/warn/error; custom spans around provisioning steps and Service Binding calls | Production Workers without telemetry are a black box. Traces auto-instrument fetch, bindings, RPC between Workers, and handlers with no SDK, so the admin → portal calls and D1 queries are visible end to end. head\_sampling\_rate is fixed at 1.0 (100%) for both logs and traces on every Worker and is never lowered; retention is Cloudflare's maximum, which is 7 days for Workers Logs and Workers Traces on Workers Paid (not configurable today; Cloudflare has announced longer options to come). From 2026-12-01 persisted logs and traces count toward Cloudflare Observability allowances (Paid: 50 GB ingestion and 10 GB-month storage per cycle, then $0.25/GB and $0.10/GB-month), which at this system's volume is well inside the included amount. Glimpse templates carry the same settings so every stamped-out glimpse is observable from its first request |

## 5. Glimpse lifecycle

A glimpse moves through the states below (srt domain GLIMPSE\_STATE). Every transition is recorded in the system database with who or what caused it. The four active states are simply the prospect's latest action; none of them changes the prospect's access.

| State | Entered when | Prospect access | Repos | Exit |
| --- | --- | --- | --- | --- |
| PROVISIONING | Ed submits the create form | None | Being created | → DRAFT on success; → FAILED on error (partial resources flagged, resumable) |
| DRAFT | Provisioning completes with Hello World deployed | None (Access app exists; prospect not yet on the policy) | Private, live | → PENDING when Ed clicks "Notify prospect" |
| PENDING | Ed notifies the prospect; `activated_at` = now | Full, via Access OTP | Private, live | → APPROVED / DECLINED / DELAYED on the prospect's action; → EXPIRED at `expires_at` |
| APPROVED | Prospect approves (portal → `record_decision`) | Full until expiry | Private | May change to DECLINED or DELAYED; Ed may delete when the real site goes live; → EXPIRED |
| DECLINED | Prospect declines | Full until expiry | Private | May change to APPROVED or DELAYED; Ed may delete; → EXPIRED |
| DELAYED | Prospect presses "I need more time" (portal → `extend`); both clocks reset | Full until the new expiry | Private | May change to APPROVED or DECLINED, or DELAYED again; → EXPIRED |
| EXPIRED | 7 days after the latest activation (cron) | Deactivated: prospect dropped from the Access policy; portal shows the glimpse as expired with its link disabled; Worker and content untouched | Private, content retained | → PENDING on Ed's Reactivate; → DELAYED on the prospect's "I need more time"; → DELETED at `delete_at` |
| DELETED | 30 days after the latest activation (cron), or Ed requests deletion | None | Both repos deleted; Workers, Routes, D1, Access app removed | Terminal; a returning prospect gets a new glimpse with a new ID |

**Scheduled events.** Two per glimpse, stored as rows and created at every activation: `EXPIRE` at activation + 7 days and `DELETE` at activation + 30 days. The admin UI and portal UI show each as a date and time in the viewer's time zone; the cron expression and next-run timestamp are stored on the row and never shown in the UI. **Reactivate** (Ed, from EXPIRED, any time before deletion) returns the glimpse to PENDING: it restores the prospect's email to the Access policy, re-enables the link in the portal, cancels the pending `DELETE` job, and creates fresh `EXPIRE` and `DELETE` jobs from the reactivation time, so every activation buys the prospect 7 days of access and pushes deletion out to 30 days from that activation. Expiry never touches repos, Workers, or content; only deletion does.

**"I need more time."** The portal shows this button on every glimpse that is active (PENDING, APPROVED, DECLINED, DELAYED) or EXPIRED, not yet deleted. Pressing it extends the glimpse immediately, with no approval step, and sets the state to DELAYED: `portal-api` appends a DELAYED row to `decision_log` and calls `admin-api`, which runs the Reactivate steps (`expires_at` = now + 7 days, `delete_at` = now + 30 days, Access policy restored if the glimpse had expired, new `EXPIRE` and `DELETE` jobs). Ed is notified by email and SMS; the prospect sees the new expiry date at once and receives a confirmation. There is no limit on extensions; Ed can see the count and dates in the admin UI and may request deletion at any time if a prospect is stalling.

**Operator actions.** Create, Notify prospect, Reactivate (from EXPIRED, any time before deletion), Request deletion (allowed from APPROVED, DECLINED, DELAYED, or EXPIRED), Re-create (creates a new glimpse for the same company; the old one is left in its state).

**Q1 resolved 2026-11-09:** `delete_at` is 30 days after the most recent activation, not the first.

## 6. Security, DNS, TLS and access gating

DNS cannot be hidden, so the design makes hostnames unguessable, content unreachable without authentication, and every surface invisible to search engines.

- **DNS:** exactly one record is created by hand: a proxied `AAAA` record named `*.glimpse` with content `100::` (Cloudflare's placeholder for "the Worker is the origin"). It covers `admin`, `portal`, and every glimpse hostname (APIs live under `/api/*` on the same hosts), so no per-glimpse DNS record ever exists and the zone reveals nothing. Zone transfers disabled; Domain Name System Security Extensions (DNSSEC) on. Each tier's two Workers are attached with Workers **Routes** on one hostname (`<host>.glimpse.andexor.net/api/*` to the API Worker, `<host>.glimpse.andexor.net/*` to the UI Worker; the more specific route wins), not Custom Domains: Custom Domains create a DNS record and issue a separate Advanced Certificate per hostname (which would log every glimpse ID to Certificate Transparency and is capped at 100 per zone), whereas Routes create nothing and allow 1,000 per zone.
- **TLS:** Advanced Certificate Manager (ACM) is active on the `andexor.net` zone with one certificate covering `andexor.net`, `*.andexor.net`, `glimpse.andexor.net`, and `*.glimpse.andexor.net` (provisioned 2026-11-09). Universal SSL covers only one label below the apex, so ACM is required for the two-level glimpse hostnames. Because Routes issue no certificates, this single wildcard is the only certificate in play and Certificate Transparency (CT) logs never show a glimpse ID.
- **Access gating:** one Cloudflare Access application per hostname (the UI at / and its API at /api/\* share it): one for admin, one for portal, one per glimpse. Email OTP for prospects; policy = allow-listed addresses. Admin hosts allow Ed only; the portal allows every prospect with a notified glimpse; each glimpse host allows that prospect's email plus Ed. Session duration 7 days, shared across all applications, so one PIN entry covers portal and glimpse. Requests that fail Access never reach a Worker; a visitor whose email is not on the list is never sent a PIN. The glimpse hostname is directly reachable by anyone who passes its own sign-in: the portal is the natural way in (it always shows the glimpse link) but not a mandatory gate, so the prospect can open the glimpse from the invite, a bookmark, or a phone. Because the prospect's email is what Access authenticates, it is a required input when a glimpse is created. Zero Trust organization: team name andexor, Free plan, created 2026-11-09. New organizations default to the Cloudflare identity provider, so the One-time PIN login method must be added once under Integrations → Identity providers (done by Ed). Admin hosts offer the Cloudflare identity provider (Ed signs in with his Cloudflare account and its MFA); portal and glimpse hosts offer OTP only. OTP emails come from noreply@notify.cloudflare.com; the invite template tells prospects to expect that sender.
- **Prospect with no email:** not supported; email is required at creation. A phone number, when known, is used only for SMS copies of the invite and alerts.
- **Robots:** `X-Robots-Tag: noindex, nofollow` injected by a Cloudflare Transform Rule on `*.glimpse.andexor.net`; each app also serves `robots.txt` (disallow all) and a `<meta name="robots" content="noindex, nofollow">` tag; no sitemap; no canonical pointing at a glimpse host.
- **Secrets:** every credential the system holds (GitHub token, Cloudflare API tokens, future email/SMS provider keys, signing keys) lives in Cloudflare Secrets Store, the account-level store, never as per-Worker wrangler secrets, environment variables, or repo contents. Each Worker declares a `secrets_store_secrets` binding for only the secrets it needs and reads them at runtime with the binding's asynchronous `get()`; a Worker without a binding to a secret cannot obtain it. Secrets are scoped to `workers` and named `<system>-<purpose>` (e.g. `glimpse-github-token`, `glimpse-d1-edit-token`). Constraints verified 2026-11-09: Secrets Store is in open beta with one store per account and 100 secrets per account, so glimpses must not consume secrets — Hello World needs none (Access handles authentication, D1 is reached by binding) and any real design that needs a third-party key draws on the shared budget deliberately. GitHub Actions deploy tokens need Account Secrets Store Edit to deploy a Worker with such a binding. No credentials in any repo, including generated glimpse repos; `.dev.vars` holds test values only and is git-ignored.
- **Isolation:** each glimpse has its own Worker, D1 database, Access application, and repos. Nothing in a glimpse can address another glimpse's resources.
- **Retirement:** Expired glimpses lose the prospect from the Access policy and have the Worker route disabled; Deleted glimpses have every Cloudflare resource and both repos removed. The old hostname returns Cloudflare's default error, never a redirect.

## 7. Data model

Three kinds of database, none shared and none replicated. The **system database** (owned by `admin-api`) holds the glimpse lifecycle, provisioning, and scheduling; its entities are the table below, which contains no feedback. The **portal database** (owned by `portal-api`) is the only home for prospect feedback: `glimpse` (`glimpse_id`, `company_name`, `prospect_email`, `hostname`, `expires_at`, `active`); `decision_log` (`id`, `prospect_id`, `glimpse_id`, `action` APPROVED/DECLINED/DELAYED, `occurred_at`, `new_expires_at` on DELAYED rows); `comment`. `decision_log` is append-only: every press of Approve, Decline, or "I need more time" adds a row, and a glimpse's current decision is its latest APPROVED or DECLINED row. Each **glimpse database** holds only that glimpse's runtime data.

The two APIs are independent systems that exchange the minimum: at notify, reactivate, extend, expire, and delete, `admin-api` sends `portal-api` one `upsert_glimpse` command over a Service Binding carrying the glimpse record (id, prospect, company, hostname, `expires_at`, `active`, `deleted`). In the other direction portal-api makes exactly two calls: extend when a prospect presses "I need more time", and record\_decision when a prospect approves or declines, so the glimpse state in the system database is always the prospect's latest action while the decision text never leaves the portal database. Nothing flows on a schedule; when Ed opens a glimpse in the admin UI, `admin-api` fetches that glimpse's decision and comments from `portal-api` on demand and displays them without storing them. There is no reconciliation job because nothing is duplicated beyond the glimpse record.

| Entity | Key fields | Notes |
| --- | --- | --- |
| `srt` | `domain`, `code`, `label`, `description`, `sort_order`, `active` | System Reference Table; authoritative UPPERCASE codes, enforced by triggers |
| `prospect` | `id`, `company_name` (required), `email` (required, lowercase), `owner_name`, `phone`, `created_at` | One row per company; a company may have several glimpses over time |
| `glimpse` | `id` (20-char base32), `prospect_id`, `state` (GLIMPSE_STATE), `hostname`, `ui_repo`, `api_repo`, `ui_worker`, `api_worker`, `d1_database_id`, `access_app_id`, `notified_at`, `activated_at`, `expires_at`, `delete_at`, `deleted_at`, `extension_count`, `last_extended_at` | One row per glimpse; one hostname, one Access application |
| `glimpse_event` | `glimpse_id`, `from_state`, `to_state` (GLIMPSE_STATE), `actor` (ACTOR), `occurred_at`, `detail` | Append-only audit trail of every transition |
| `scheduled_job` | `id`, `glimpse_id`, `kind` (JOB_KIND), `run_at`, `cron_expression`, `status` (JOB_STATUS), `ran_at`, `result` | Dates shown in UIs; the cron expression lives here, not in the console; at most one PENDING job per kind per glimpse |
| `provisioning_run` / `provisioning_step` | run: `id`, `glimpse_id`, `kind` (RUN_KIND), `status` (RUN_STATUS), `trace_id`; step: `run_id`, `seq`, `name`, `status` (STEP_STATUS), `trace_id`, `log` | One run per operation, one row per step; feeds the Server-Sent Events (SSE) progress stream and supports resume |
| `notification` | `id`, `glimpse_id`, `recipient` (RECIPIENT), `channel` (CHANNEL), `template`, `status` (NOTIFICATION_STATUS), `sent_at` | Records every invite and alert admin-api sends, including stubbed ones |
| `schema_migration` | `version`, `name`, `applied_at` | Applied migrations (admin role only) |

Full DDL: `db/system/0001_init.sql`, `db/portal/0001_init.sql`, `db/glimpse/0001_init.sql`.

**Per-glimpse D1:** created with an empty `srt` and a `meta` table (`key`, `value`). Real designs add their own tables and register their own codes in `srt`. Nothing in a per-glimpse database references the system or portal databases.

**Isolation rule:** the portal API never accepts a `glimpse_id` from the client; it derives the prospect from the Access identity header and resolves glimpses server-side within the portal database, which contains no other prospect's provisioning data to leak.

## 7a. Database access control

Every component reaches a database with the least privilege it needs, following the Principle of Least Privilege (PoLP). Cloudflare D1 has no database users, roles, or per-database credentials: a Worker binding grants full read, write, and schema rights on that database, and API tokens carry account-level `D1 Read` or `D1 Edit` permission. The three roles below are therefore enforced by architecture and code, not by the database engine.

| Role | May do | Who holds it |
| --- | --- | --- |
| `reader` | `SELECT` only | Portal API reads of glimpse status; Ed's ad hoc inspection |
| `writer` | `reader` + `INSERT`/`UPDATE`/`DELETE` on rows, never schema changes | Portal API (decisions, comments, notifications); admin API runtime writes; each glimpse API on its own database |
| `admin` | `writer` + DDL (migrations), database create/delete, export, Time Travel restore | Admin API provisioning engine; the migration step of each `-api` deploy workflow |

**Enforcement layers, strongest first:**

1. **Binding scope.** Every database has exactly one Worker bound to it: the system database to admin-api, the portal database to portal-api, each glimpse database to its glimpse API; the UIs bind to none. A Worker with no binding to a database cannot reach it by any means, so no database is reachable from more than one codebase.
2. **Owner-only access across Workers.** When one API needs another's data it calls that API over a Service Binding, and the owning API exposes only the narrow methods the caller is entitled to: `portal-api` exposes exactly two (`upsert_glimpse`: accept a glimpse record; `get_feedback`: return a glimpse's decision\_log and comments) and `admin-api` exposes exactly two (`extend`: reset the clocks on "I need more time"; `record_decision`: set the glimpse state to APPROVED or DECLINED). Because Service Bindings are declared per Worker, the portal API has no path to the system database or to any admin method other than those two. This makes the roles unforgeable at the platform level without any extra Worker.
3. **Data-access layer in code.** Each `-api` has a single data-access module per role; business code imports only the role it is permitted. A statement allow-list rejects DDL from `reader`/`writer` paths. Required in every API, since each is the sole consumer of its own database and therefore the sole place the reader/writer/admin split can be enforced.
4. **API tokens.** Two account tokens, held in Cloudflare Secrets Store and bound only to `admin-api` (plus GitHub Actions secrets for the migration step): `d1-edit` (create/delete databases, run migrations, exports) and `d1-read` (Ed's inspection tooling). Scoped to D1 only, rotated on a schedule, never present in UI Workers or glimpse repos.
5. **Audit.** Every write through the `admin` role is logged to `glimpse_event` or `provisioning_run`; `wrangler d1 insights` is reviewed for unexpected statement shapes.

**Q4 (data gateway Worker):** withdrawn 2026-11-09. Ed decided on separate databases per API, which gives each database a single owning Worker and makes a gateway unnecessary.

## 8. Repository provisioning

Repository creation is a function of `admin-api`, driven from `admin-ui`, not a script Ed runs. The same code path creates the five system repos (once, public) and every glimpse repo pair (private). Settings are copied from `andexor-net-website`; the implementation step audits that repo and records the exact settings in the child PRD for `admin-api`.

| Setting | Value |
| --- | --- |
| Owner | `andexor` organization (never `ejenkins`) |
| Template | Created from `andexor-base-template`; "Template repository" left off on the new repo |
| Visibility | Public for system repos; private for glimpse repos |
| Settings tab | Preserve this repository; allow squash merging (other merge types as in `andexor-net-website`); limit branches/tags updated per push; automatically delete head branches |
| Rulesets | Same rulesets as `andexor-net-website`, applied by API |
| Security and quality | Same options as `andexor-net-website`, including Advanced Security |
| GitHub Actions | TypeScript workflow set for `-ui` repos (lint, type-check, build, deploy to Cloudflare); Python/uv workflow set for `-api` repos (lint, test, deploy via wrangler) |
| Spec Kit | `specify init --integration claude` run in each new repo; constitution inherited from `andexor-glimpse-main` |
| After creation | Star the repo as Ed; set watch to all activity |

**Glimpse Hello World:** the `-ui` repo deploys a single page that shows the company name; the `-api` repo deploys a `/health` endpoint bound to the glimpse's D1. Both are proof that the pipeline works, nothing more. Ed replaces the content manually afterwards.

**Idempotency:** every provisioning step checks for its resource before creating it, so a failed run can be resumed from the admin UI without duplicating repos, Workers, or databases.

## 9. Notifications

Two flows, both stubbed in v1: the stub writes a `notification` row with status `stubbed` and renders the template to the log, so the plumbing can be swapped for a real provider without touching callers.

| Flow | Trigger | Recipient | Channel | Content |
| --- | --- | --- | --- | --- |
| Prospect invite | Ed clicks "Notify prospect" after replacing Hello World | Prospect | Email always; SMS copy when a phone is known | Company name, glimpse link, portal link, expiry date, how sign-in works |
| Feedback alert | Prospect submits a decision or a comment (sent by portal-api) | Ed | Email and SMS | Company name, what was submitted, link to the glimpse in the admin UI |
| Extension taken | Prospect presses "I need more time" (sent by portal-api) | Ed | Email and SMS | Company name, new expiry and deletion dates, link to the glimpse in the admin UI |
| Extension confirmation | Same event | Prospect | Email (SMS copy if phone known) | New expiry date, glimpse link |
| Lifecycle notice (optional, v1.1) | Expire or delete job runs | Ed | Email | Which glimpse, which event |

**Templates:** one file per channel per flow under `admin-api` (`templates/email/*.html`, `templates/sms/*.txt`), with named placeholders; Ed edits these directly. The provider interface takes `(channel, recipient, template, variables)` and returns a delivery ID. Provider details for email and SMS are deferred until Ed has them operational elsewhere.

## 10. UX and performance requirements

These apply to `admin-ui` and `portal-ui`. Glimpse UIs inherit only the robots and responsiveness rules; their look is the prospect's.

- **Responsive:** every screen works from 360 px to 1920 px wide; the two UIs share a layout grid so a form or table looks the same in both.
- **Button feedback:** any button that calls a REST API animates down and up (pressed state) before the request is sent, and is disabled until the response or the first SSE event arrives.
- **Long operations:** any API operation measured over 1 second in testing returns `202 Accepted` with a job ID, runs asynchronously, and streams progress over Server-Sent Events (SSE). Provisioning a glimpse is the known case: the admin UI shows each step from `provisioning_run` as it completes. Performance testing of every endpoint is a required task in each `-api` child PRD.
- **Dates and times:** shown in the viewer's time zone with the zone named; never as a cron expression.
- **Cookiebot:** included as in `andexor-net-website`; verifying it under CSR is an explicit task.
- **Design system:** FontAwesome icons, the same Google Fonts, and the Andexor Network Design System tokens and components used by `andexor-net-website`.
- **Observability:** every Worker ships with `observability.enabled`, `observability.traces.enabled`, and `observability.issues.enabled` set to true and head\_sampling\_rate = 1.0 for both logs and traces; data is kept for Cloudflare's full retention window (7 days) and allowed to expire naturally; logs are structured JSON with a request ID that the UIs echo in error messages so Ed can find the matching trace; provisioning steps and Service Binding calls carry custom spans named after the step; an SSE progress event includes the trace ID for the step it reports.
- **Accessibility:** keyboard-operable, labelled controls, visible focus, contrast at WCAG 2.2 AA (Web Content Accessibility Guidelines); the glimpse pitch includes accessibility, so the admin and portal must model it.
- **Admin dashboard:** one table of glimpses with company, state, notified, expires, deletes, decision, comment count; filter by state; an extensions count per glimpse with the latest extension date; row actions for Notify, Reactivate, Request deletion, Re-create.
- **Prospect portal:** one page per glimpse with the preview link, expiry date, Approve and Decline buttons, an "I need more time" button, and a comment thread; approving or declining asks for confirmation and can be changed later; the more-time button updates the expiry date on screen as soon as the extension completes.

## 11. Risks, constraints and open questions

| # | Risk or question | Why it matters | Resolution path |
| --- | --- | --- | --- |
| R1 | FastAPI on Python Workers: dependency support and cold-start time | Pyodide runs pure-Python packages well; anything with native extensions may not load, and cold starts can exceed the 1-second async threshold | Discovery pass in Claude Code against `andexor-net-website-contact-us`: list its dependencies, measure cold start, confirm SSE works from a Python Worker |
| R2 | D1 database count per account | Verified 2026-11-09: Workers Free allows 10 D1 databases per account; Workers Paid ($5/month) includes 100,000. Ed subscribed to Workers Paid on 2026-11-09 (to be confirmed via the account subscriptions API during discovery), so the 10-database cap no longer applies | Resolved by the Workers Paid subscription (also lifts the D1 daily read/write caps enforced on Free since 2026-09-01 and raises Workers per account from 100 to 500; each glimpse uses 2 Workers, so Paid supports roughly 240 concurrent glimpses after the system's own Workers) |
| R3 | Cloudflare Access user count | Free plan covers 50 users; each prospect email is a user until removed | Expire removes the prospect from the policy, which frees the seat; monitor count in the admin dashboard |
| R4 | Prospect email required for Access OTP | A prospect without an email cannot be given a glimpse | Resolved: email is a required input alongside company name; Ed collects it before creating the glimpse |
| R5 | Provisioning is many API calls across two providers | Partial failures leave orphaned repos or Workers | Idempotent steps, `provisioning_run` log, resume from admin UI, nightly orphan sweep |
| R6 | 30-day deletion is irreversible | A prospect returning on day 31 gets nothing back | Accept: a new glimpse is created; design content Ed wants to keep is his to copy out before `delete_at` |
| R7 | Spec Kit in generated glimpse repos adds files the prospect's real design may not want | Noise in a repo Ed hands off or rebuilds | Keep Spec Kit in the `-ui`/`-api` pair; Ed may remove it when replacing Hello World |
| R8 | Cookiebot under CSR | Consent script behaviour differs when there is no server render | Explicit verification task in `admin-ui` child PRD |
| Q1 | `delete_at`: 30 days after first activation or after the latest activation? | Resolved: 30 days after the most recent activation; each reactivation resets both clocks | Closed 2026-11-09 |
| Q2 | Does a per-glimpse `-api` need to exist for Hello World, or only when a real design needs one? | Resolved: both repos, both Workers, and the glimpse database are provisioned up front for every glimpse | Closed 2026-11-09 |
| Q3 | Should the prospect portal be one shared app or per-glimpse? | Resolved: one shared portal app and database, scoped server-side by the Access identity | Closed 2026-11-09 |
| Q5 | Portal SRT domain DECISION\_ACTION (APPROVED, DECLINED, DELAYED) vs reusing the name GLIMPSE\_STATE for the same three codes | Naming only; codes are identical by design. Separate name says 'action', shared name says 'same vocabulary' | Deferred 2026-11-09: keep DECISION\_ACTION for now; review after implementation starts |

## 12. Child PRDs

Each project gets its own PRD, written after this master is approved and kept in its own repo under `docs/PRD.md`, then turned into Spec Kit artefacts (`spec.md`, `plan.md`, `tasks.md`). The master governs: a child may refine but not contradict it, and any conflict is resolved by amending the master first.

| Child PRD | Repo | Owns |
| --- | --- | --- |
| Governing repo | `andexor-glimpse-main` | Spec Kit constitution, PlantUML component, sequence (provisioning, feedback), and state (lifecycle) diagrams, naming standard, this PRD |
| Admin UI | `andexor-glimpse-admin-ui` | Dashboard, create form, SSE progress view, row actions, date display, Cookiebot verification |
| Admin API | `andexor-glimpse-admin-api` | Provisioning engine, GitHub and Cloudflare integration, system D1 schema and migrations, scheduled jobs, notification stubs and templates, SSE |
| Portal UI | `andexor-glimpse-portal-ui` | Prospect sign-in experience, glimpse page, approve/decline, comments |
| Portal API | `andexor-glimpse-portal-api` | Prospect-scoped reads, decision and comment writes, Ed alerts |
| Glimpse templates | `andexor-glimpse-main` (templates folder) | The Hello World `-ui` and `-api` templates stamped into each glimpse repo pair, including their workflows and Spec Kit scaffold |

Implementation order: governing repo → admin API (with provisioning of the other system repos as its first real job) → admin UI → glimpse templates → portal API → portal UI.

## 13. Readiness checklist

**Cloudflare account state (verified 2026-11-09 via the Cloudflare Developer Platform connector):** 2 Workers (`andexor-net-website`, `andexor-net-website-contact-us`), 1 D1 database (`andexor-net-website-contact-us`), nothing deployed under `glimpse.andexor.net`, Workers Paid plan per Ed (subscribed 2026-11-09; not visible through the connector, confirm during discovery), ACM active with the wildcard certificate above.

Implementation starts when every item is ticked.

- [x] Ed confirms the naming standard (`ui`/`api`, `-main` governing repo) and the `glimpse.andexor.net` hostnames
- [x] Q1–Q4 answered (all closed 2026-11-09)
- [ ] Discovery in Claude Code: `andexor-net-website-contact-us` dependencies, cold start, and SSE on Python Workers (R1)
- [ ] Discovery in Claude Code: D1 database limit and Access user limit on the current plans (R2, R3)
- [ ] Discovery in Claude Code: exact settings, rulesets, and security options on `andexor-net-website` recorded for section 8
- [ ] GitHub MCP server and `gh` authenticated as Ed; Cloudflare MCP server and `wrangler` authenticated; both verified with a read-only call
- [x] Lifecycle table (section 5) and data model (section 7) reviewed and accepted by Ed
- [ ] Notification template placeholders agreed
- [x] Child PRD list and implementation order accepted
- [x] Master PRD committed to `andexor-glimpse-main` as `docs/PRD.md` (this file); Spec Kit constitution to be drafted from `CLAUDE.md` and sections 4 and 6
