-- andexor-glimpse-<id>-api — per-glimpse database
-- Owner: that glimpse's API Worker only. Created empty by admin-api during
-- provisioning; Hello World uses only `meta`. A real design adds its own
-- tables in later migrations within the glimpse repo and registers any
-- finite-value codes it needs in srt. Nothing here references the system or
-- portal databases.
-- Dialect: SQLite (Cloudflare D1). Migration 0001.

PRAGMA foreign_keys = ON;

-- ---------------------------------------------------------------------------
-- srt: System Reference Table. The authoritative list of every finite-value
-- code used in this database. Codes are UPPERCASE. Triggers below reject any
-- write whose code is not an active row here, so adding a value is a migration
-- that inserts into srt, never a code change.
-- ---------------------------------------------------------------------------
CREATE TABLE srt (
    domain      TEXT NOT NULL,                       -- e.g. GLIMPSE_STATE
    code        TEXT NOT NULL,                       -- e.g. PENDING
    label       TEXT NOT NULL,                       -- short UI label
    description TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    active      INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    PRIMARY KEY (domain, code),
    CHECK (domain = upper(domain) AND code = upper(code))
);
CREATE INDEX srt_domain_idx ON srt(domain, sort_order);

CREATE TABLE meta (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    updated_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
-- Populated by admin-api at creation:
--   glimpse_id    -> 20-char lowercase base32 id
--   company_name  -> prospect company name (display only)
--   created_at    -> ISO-8601 UTC

CREATE TABLE schema_migration (
    version     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    applied_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
INSERT INTO schema_migration (version, name) VALUES (1, '0001_init');
