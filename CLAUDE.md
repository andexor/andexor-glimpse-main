# andexor-glimpse-main — governing repository for Andexor Glimpse

This repo governs the Andexor Glimpse family. It holds no runtime code. Read this file, then `docs/PRD.md`, before doing anything in this repo or in any `andexor-glimpse-*` repo.

## Source of truth

- **`docs/PRD.md`** is the master Product Requirements Document (PRD). Every child repo's `docs/PRD.md` and Spec Kit artefacts (`spec.md`, `plan.md`, `tasks.md`) refine it and may not contradict it. A conflict is resolved by amending the master first, then the child.
- **`db/`** holds the Data Definition Language (DDL) for the three database kinds (system, portal, glimpse). Schema changes are numbered migrations; see `db/README.md`.
- **`api/`** holds the hand-drafted OpenAPI 3.1 contracts for `admin-api` and `portal-api`, including the `x-service-bindings` sections that define the four Worker-to-Worker methods. Once code exists, FastAPI's generated spec replaces these files; the Service Binding contract stays here.
- **`docs/diagrams/`** holds PlantUML sources (component, lifecycle state machine, sequences). Render them in CI; do not commit rendered images by hand.

## Standing conventions (apply in every Andexor repo)

1. **Naming.** Repos, Workers, databases, and apps are `andexor-<system>[-<component>]-<tier>`; tier is `ui` (front end) or `api` (back end). The governing repo is `andexor-<system>-main`. Glimpse repos are `andexor-glimpse-<id>-ui` and `-api`. Everything goes in the `andexor` GitHub organization, never `ejenkins`. System repos are public; glimpse, sandbox, and test repos are private. A client's own copies, made at handoff, default to private (PRD section 8).
2. **Identifiers are lowercase.** Universally Unique Identifiers (UUIDs), hexadecimal codes, and glimpse IDs (20-character base32) are lowercase everywhere — database, logs, UIs, hostnames, Cloudflare resource names — per RFC 4122. No prefixes.
3. **Finite-value fields are UPPERCASE codes from the System Reference Table (SRT).** Every database has an `srt` table; triggers reject codes not present in it. Adding a value is a migration that inserts into `srt`, never a code edit. UIs read labels and ordering from `srt`. Glimpse states: `PROVISIONING`, `FAILED`, `DRAFT`, `PENDING`, `APPROVED`, `DECLINED`, `DELAYED`, `EXPIRED`, `DELETED`.
4. **CSS hex colours are uppercase** (`#1A73E8`); Stylelint `color-hex-case: upper`. This is a separate rule from (2), not an exception to it.
5. **Documentation spells out names on first use** with the acronym in parentheses — Cloudflare Access, Server-Sent Events (SSE), Principle of Least Privilege (PoLP). This applies to each document independently. Do not begin using an acronym in one document simply because it is defined elsewhere.
6. **One database, one Worker.** No database is shared or replicated. `admin-api` owns the system database, `portal-api` owns the portal database, each glimpse API owns its own. Cross-system data moves only through the four Service Binding methods: `portal-api.upsert_glimpse`, `portal-api.get_feedback`, `admin-api.extend`, `admin-api.record_decision`.
7. **Database roles** (`reader`, `writer`, `admin`) are enforced by binding scope, a role-split data-access module with a statement allow-list, and which token a process holds. Runtime code never issues DDL; migrations run from the deploy workflow with the `glimpse-d1-edit-token`.
8. **Secrets live in Cloudflare Secrets Store** and are bound per Worker (`secrets_store_secrets`). Never per-Worker `wrangler secret`, never environment variables, never in a repo. Glimpses need no secrets by design: a D1 database is reached by Worker binding (no credential), Access handles authentication, and only the system Workers call external services. Secrets Store caps at 100 secrets per account, so a real design that needs a third-party key draws on that shared budget as a deliberate, recorded decision.
9. **Routing.** One hostname per tier (`admin`, `portal`, `<id>` under `glimpse.andexor.net`). Two Workers Routes per hostname, where `<host>` stands for the full hostname: `<host>/api/*` → API Worker, `<host>/*` → UI Worker (the more specific route wins). For example, `admin.glimpse.andexor.net/api/*` → `andexor-glimpse-admin-api` and `admin.glimpse.andexor.net/*` → `andexor-glimpse-admin-ui`; a glimpse uses `<id>.glimpse.andexor.net/api/*` and `<id>.glimpse.andexor.net/*`. Never Workers Custom Domains (they issue per-hostname certificates and create DNS records). One Cloudflare Access application per hostname. The only hand-made DNS record is the proxied `AAAA *.glimpse → 100::`.
10. **Observability.** Every Worker sets `observability.enabled`, `observability.traces.enabled`, `observability.issues.enabled` to `true` with `head_sampling_rate = 1.0` for logs and traces; structured JSON logs; a `request_id` in every error response.
11. **Robots.** Every host serves `X-Robots-Tag: noindex, nofollow`, a disallow-all `robots.txt`, and a `<meta name="robots">` tag; no sitemaps; outbound links `rel="nofollow"`.
12. **Stack.** Next.js (latest, Client Side Rendering) on Node via nvm for `-ui`; FastAPI (latest) on Cloudflare Python Workers via uv for `-api`; Cloudflare D1; no Bun, no Docker unless a reason is recorded in the PRD.
13. **Spec Kit.** `specify init --integration claude` in every repo; the constitution lives here in `.specify/memory/constitution.md` and is copied, not rewritten, into child repos.
14. **API conventions.** Every endpoint is versioned (`/api/v1/<resource>`); the only exception is the health check at `/api/health`, which is unversioned, makes no external calls, and reports on none. Routes are always written as the full path a caller types. Every call to an external resource sits in an error handler that logs failures. No metrics in logs: take timings from traces.
15. **Gated deployment.** Every `-api` repo deploys to a preview Worker and database, passes a smoke test (health check plus a real call to every versioned endpoint, preview only), and only then deploys to production, with a required status check on the default branch. See `docs/PRD.md` section 8a.

## Working in this repo

- Before changing `db/*.sql`, run the schema check: `python3 tools/check_schemas.py` (loads each `0001_init.sql` into SQLite and runs the constraint tests). Regenerate SRT triggers with `tools/gen_srt_triggers.py`; never hand-edit them.
- Before changing `api/*.yaml`, validate: `python3 -c "import yaml,sys; [yaml.safe_load(open(f)) for f in sys.argv[1:]]" api/*.yaml`.
- Keep `docs/PRD.md` section numbers stable; child PRDs cite them.
- Cloudflare account facts as of 2026-11-09: zone `andexor.net`; ACM certificate covering `andexor.net`, `*.andexor.net`, `glimpse.andexor.net`, `*.glimpse.andexor.net`; Workers Paid plan; Zero Trust organization `andexor` (Free), One-time PIN identity provider added. Verify with read-only calls (`wrangler whoami`, account subscriptions API) before the first write.
- GitHub: `gh auth status` must show the `andexor` organization before any repo operation.

## Implementation order (PRD section 12)

`andexor-glimpse-main` → `andexor-glimpse-admin-api` (its first real job is provisioning the other system repos) → `andexor-glimpse-admin-ui` → glimpse templates (in this repo under `templates/`) → `andexor-glimpse-portal-api` → `andexor-glimpse-portal-ui`.

## Open items carried from the PRD

- Client handoff (PRD section 8): the first client who prefers a Git host other than GitHub or a platform other than Cloudflare triggers a custom migration solution, built to be repeatable for other clients through variables. Until then, no handoff automation exists.
- Discovery before `admin-api` work: FastAPI dependency support and cold-start time on Python Workers; SSE from a Python Worker; exact settings, rulesets, and security options on `andexor-net-website` to copy into provisioning.
