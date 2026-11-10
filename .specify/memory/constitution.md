# Andexor Glimpse Constitution

This constitution governs the whole Andexor Glimpse family: `andexor-glimpse-main` and every
`andexor-glimpse-*` repository. It is authored here and copied, not rewritten, into child repos.

## Core Principles

### I. Naming and Identifiers

Repos, Workers, databases, and apps MUST be named `andexor-<system>[-<component>]-<tier>`, where
tier is `ui` (front end) or `api` (back end). The governing repo is `andexor-<system>-main`.
Glimpse repos are `andexor-glimpse-<id>-ui` and `-api`. Everything lives in the `andexor` GitHub
organization, never a personal account. System repos are public; glimpse, sandbox, and test repos are private.

Universally Unique Identifiers (UUIDs), hexadecimal codes, and glimpse IDs (20-character base32)
MUST be lowercase everywhere: database, logs, UIs, hostnames, and Cloudflare resource names, per
RFC 4122. Identifiers MUST NOT carry prefixes.

Rationale: predictable names make provisioning idempotent and resources findable; one case rule
removes comparison bugs.

### II. Reference Data Lives in the System Reference Table

Every finite-value field MUST hold an UPPERCASE code from the System Reference Table (SRT). Every
database MUST have an `srt` table, and triggers MUST reject codes not present in it. Adding a value
is a migration that inserts into `srt`, never a code edit. UIs MUST read labels and ordering from
`srt`. SRT triggers MUST be regenerated with `tools/gen_srt_triggers.py`, never hand-edited.
Glimpse states are `PROVISIONING`, `FAILED`, `DRAFT`, `PENDING`, `APPROVED`, `DECLINED`,
`DELAYED`, `EXPIRED`, and `DELETED`.

Rationale: the database is the single authority on valid values, so code and UI cannot drift.

### III. One Database, One Worker, Least Privilege

No database is shared or replicated. `admin-api` owns the system database, `portal-api` owns the
portal database, and each glimpse API owns its own. Cross-system data MUST move only through the
four Service Binding methods: `portal-api.upsert_glimpse`, `portal-api.get_feedback`,
`admin-api.extend`, and `admin-api.record_decision`. The contract for these stays in `api/`.

Database roles (`reader`, `writer`, `admin`) MUST be enforced by binding scope, a role-split
data-access module with a statement allow-list, and which token a process holds. Runtime code MUST
NOT issue DDL. Schema changes are numbered migrations in `db/`, run from the deploy workflow with
the `glimpse-d1-edit-token`.

Rationale: each Worker can reach only its own data, so a compromise or bug has a bounded blast
radius (Principle of Least Privilege, PoLP).

### IV. Secrets and Access Control (NON-NEGOTIABLE)

Secrets MUST live in Cloudflare Secrets Store and be bound per Worker with `secrets_store_secrets`.
They MUST NOT be per-Worker `wrangler secret` values, environment variables, or repo contents.
Glimpses MUST need no secrets by design: a D1 database is reached by Worker binding, Access
handles authentication, and only the system Workers call external services. A real design that
needs a third-party key MUST draw on the shared Secrets Store budget (100 secrets per account) as
a recorded decision. `.dev.vars` holds test values only and is git-ignored.

Every hostname MUST sit behind one Cloudflare Access application. Admin hosts allow Ed only; the
portal allows prospects with a notified glimpse; each glimpse host allows that prospect plus Ed.

Rationale: a Worker without a binding cannot obtain a secret, and requests that fail Access never
reach a Worker.

### V. Routing

There MUST be one hostname per tier: `admin`, `portal`, and `<id>` under `glimpse.andexor.net`.
Each hostname MUST have two Workers Routes, where `<host>` stands for the full hostname:
`<host>/api/*` to the API Worker and `<host>/*` to the UI Worker (the more specific route wins).
For example, `admin.glimpse.andexor.net/api/*` goes to `andexor-glimpse-admin-api` and
`admin.glimpse.andexor.net/*` goes to `andexor-glimpse-admin-ui`; a glimpse uses
`<id>.glimpse.andexor.net/api/*` and `<id>.glimpse.andexor.net/*`. Workers Custom Domains MUST NOT be used, because they issue per-hostname certificates and
create DNS records. The only hand-made DNS record is the proxied `AAAA *.glimpse` to `100::`.

Rationale: Routes create no DNS records and no certificates, so no glimpse ID ever appears in
Certificate Transparency logs or the zone.

### VI. Observability and Robots

Every Worker MUST set `observability.enabled`, `observability.traces.enabled`, and
`observability.issues.enabled` to `true`, with `head_sampling_rate = 1.0` for logs and traces.
Logs MUST be structured JSON, and every error response MUST include a `request_id`. Metrics and
statistical data (timings, durations, counts) MUST NOT be written to logs unless there is no other
way to obtain them. Timings MUST be taken from Workers traces and invocation records, which
already carry timestamps, wall time, and CPU time. Where Cloudflare offers no alternative (it does
not yet support OpenTelemetry metrics), a log-based metric is allowed only as a recorded
exception in the PRD.

Every host MUST serve `X-Robots-Tag: noindex, nofollow`, a disallow-all `robots.txt`, and a
`<meta name="robots">` tag. Sitemaps MUST NOT exist, and outbound links MUST carry
`rel="nofollow"`.

Rationale: production Workers without telemetry are a black box; all surfaces are internal or
prospect-only and must stay out of search indexes.

### VII. Specification-Driven Development

`docs/PRD.md` in this repo is the master Product Requirements Document (PRD). Every child repo's
`docs/PRD.md` and Spec Kit artefacts (`spec.md`, `plan.md`, `tasks.md`) MUST refine it and MUST NOT
contradict it. A conflict MUST be resolved by amending the master first, then the child. PRD
section numbers MUST stay stable because child PRDs cite them. Every repo MUST be initialised with
`specify init --integration claude`.

Rationale: one source of truth prevents divergent requirements across a family of repos.

### VIII. API Conventions

Every REST API endpoint MUST be versioned in its path, as in `/api/v1/<resource>`. The only
exception is the health check.

Every REST API app MUST expose a health check at exactly `/api/health`, with no version in the
path and no other spelling (no `/health`, no `/api/<name>/health`). The health check MUST make no
external calls of any kind: no database, no Service Binding, no Secrets Store read, no network
request. It MUST NOT report on any external resource. It reports only that the Worker is running.

Every communication with an external resource (database, Service Binding, Secrets Store, third-party
API) MUST be enclosed in an error handler that logs the failure. The caller receives only a generic
JSON error that includes the `request_id`; detail stays in the logs. An unhandled error MUST be
caught by middleware, logged, and returned in the same shape.

A route is always written as the full path a caller types, for example `/api/v1/glimpses` or
`/api/health`, in every document, contract, test, and diagram.

Rationale: a health check that depends on other systems cannot separate "the Worker is up" from
"something it depends on is down", and it adds latency and failure modes to every probe. Dependencies
are exercised by the pre-production smoke test (Principle IX), not by the health check. One
unversioned path lets deploy scripts and monitors probe every API the same way.

### IX. Gated Deployment

Every `-api` repo MUST deploy to a preview Worker with its own preview database before production,
and a smoke test MUST pass there first: a health check on `/api/health` (with retries, because a
fresh deploy can take seconds to answer) and a real call to every versioned endpoint, run only
against the preview and its database. The preview check MUST be a required status check on the default branch, so a failing
preview blocks the merge until it is fixed, and the production deploy MUST run only after the pull
request is merged and the preview has passed, and MUST end with a health check on `/api/health`.
Real test calls MUST never be made against production. A call with external side effects
(anything beyond the service's own database, such as creating a GitHub repo or calling another
Worker) MUST target dedicated sandbox resources with credentials that cannot reach production.
Test data and resources created in preview MUST be kept by default, especially after a failure,
for post-mortem review; removing them is decided case by case.

Rationale: a bad change must never reach production, and the gate must not depend on a manual step
that gets forgotten. Details are in PRD section 8a.

## Additional Constraints

- **Stack.** `-ui` repos use the latest Next.js (Client Side Rendering) on Node via nvm. `-api`
  repos use the latest FastAPI on Cloudflare Python Workers, managed with uv. Data is Cloudflare
  D1. Bun and Docker MUST NOT be used unless a reason is recorded in the PRD.
- **CSS colours.** CSS hex colours MUST be UPPERCASE (`#1A73E8`); Stylelint `color-hex-case:
  upper` enforces it. This is a separate rule from Principle I's lowercase identifiers, not an
  exception to it.
- **Documentation.** Names MUST be spelled out on first use with the acronym in parentheses, for
  example Cloudflare Access, Server-Sent Events (SSE), Principle of Least Privilege (PoLP).
- **Cloudflare account facts** (as of 2026-11-09): zone `andexor.net`; ACM certificate covering
  `andexor.net`, `*.andexor.net`, `glimpse.andexor.net`, and `*.glimpse.andexor.net`; Workers Paid
  plan; Zero Trust organization `andexor` (Free) with One-time PIN. These MUST be verified with
  read-only calls (`wrangler whoami`, account subscriptions API) before the first write.

## Development Workflow

- Before changing `db/*.sql`, run `python3 tools/check_schemas.py`.
- Before changing `api/*.yaml`, validate that every file parses as YAML. Once code exists,
  FastAPI's generated spec replaces these files, but the Service Binding contract stays here.
- PlantUML sources in `docs/diagrams/` MUST be rendered in CI; rendered images MUST NOT be
  committed by hand.
- `gh auth status` MUST show the `andexor` organization before any repo operation.
- Implementation order follows PRD section 12: `andexor-glimpse-main`, `admin-api`, `admin-ui`,
  glimpse templates, `portal-api`, `portal-ui`.

## Governance

This constitution supersedes other practices in the Andexor Glimpse family. Amendments MUST be
made in `andexor-glimpse-main` through a pull request that states the rationale, updates this file
and any affected PRD sections, and lists child repos that need the copied constitution refreshed.
Child repos MUST NOT edit their copy independently.

Versioning follows semantic versioning: MAJOR for backward-incompatible removal or redefinition of
a principle; MINOR for a new principle or section or materially expanded guidance; PATCH for
clarifications and wording fixes.

Every pull request and Spec Kit plan MUST be checked for compliance with these principles, and any
deviation MUST be justified in writing in the plan or the PRD. Runtime guidance for agents is in
`CLAUDE.md`.

**Version**: 1.0.0 | **Ratified**: 2026-11-10 | **Last Amended**: 2026-11-10
