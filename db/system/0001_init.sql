-- andexor-glimpse-admin-api — system database (system of record)
-- Owner: admin-api only. No other Worker is bound to this database.
-- Dialect: SQLite (Cloudflare D1). Migration 0001.
--
-- Conventions
--   * Identifiers the system generates are lowercase (RFC 4122 style).
--   * Finite-value fields hold UPPERCASE codes defined in srt (System Reference
--     Table) and are enforced by triggers; see the bottom of this file.
--   * Timestamps are ISO-8601 UTC text, e.g. 2026-11-09T07:25:00Z.
--   * Feedback (decisions, comments) lives only in the portal database. admin-api
--     holds the resulting glimpse state (APPROVED/DECLINED/DELAYED), reported by
--     portal-api over the record_decision Service Binding method, and fetches
--     the text on demand.

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

INSERT INTO srt (domain, code, label, description, sort_order) VALUES
  ('GLIMPSE_STATE', 'PROVISIONING', 'Provisioning', 'Resources are being created', 1),
  ('GLIMPSE_STATE', 'FAILED', 'Failed', 'A provisioning step failed; resumable', 2),
  ('GLIMPSE_STATE', 'DRAFT', 'Draft', 'Hello World deployed; prospect not yet notified', 3),
  ('GLIMPSE_STATE', 'PENDING', 'Pending', 'Prospect notified; no decision yet', 4),
  ('GLIMPSE_STATE', 'APPROVED', 'Approved', 'Prospect approved the design', 5),
  ('GLIMPSE_STATE', 'DECLINED', 'Declined', 'Prospect declined the design', 6),
  ('GLIMPSE_STATE', 'DELAYED', 'Delayed', 'Prospect asked for more time (latest action)', 7),
  ('GLIMPSE_STATE', 'EXPIRED', 'Expired', 'Access deactivated; content retained until deletion', 8),
  ('GLIMPSE_STATE', 'DELETED', 'Deleted', 'All resources and repos removed', 9),
  ('ACTOR', 'ED', 'Ed', 'Operator', 1),
  ('ACTOR', 'PROSPECT', 'Prospect', 'The prospect via the portal', 2),
  ('ACTOR', 'CRON', 'Cron', 'Scheduled job', 3),
  ('ACTOR', 'SYSTEM', 'System', 'Automatic internal action', 4),
  ('JOB_KIND', 'EXPIRE', 'Expire', 'Deactivate prospect access', 1),
  ('JOB_KIND', 'DELETE', 'Delete', 'Remove all resources', 2),
  ('JOB_STATUS', 'PENDING', 'Pending', 'Waiting to run', 1),
  ('JOB_STATUS', 'RAN', 'Ran', 'Completed', 2),
  ('JOB_STATUS', 'CANCELLED', 'Cancelled', 'Superseded by reactivation or extension', 3),
  ('JOB_STATUS', 'FAILED', 'Failed', 'Error; see result', 4),
  ('RUN_KIND', 'CREATE', 'Create', 'Initial provisioning', 1),
  ('RUN_KIND', 'REACTIVATE', 'Reactivate', 'Ed reactivated', 2),
  ('RUN_KIND', 'EXTEND', 'Extend', 'Prospect asked for more time', 3),
  ('RUN_KIND', 'EXPIRE', 'Expire', 'Cron expiry', 4),
  ('RUN_KIND', 'DELETE', 'Delete', 'Deletion', 5),
  ('RUN_STATUS', 'RUNNING', 'Running', 'In progress', 1),
  ('RUN_STATUS', 'SUCCEEDED', 'Succeeded', 'All steps done', 2),
  ('RUN_STATUS', 'FAILED', 'Failed', 'A step failed', 3),
  ('RUN_STATUS', 'CANCELLED', 'Cancelled', 'Stopped by Ed', 4),
  ('STEP_STATUS', 'PENDING', 'Pending', 'Not started', 1),
  ('STEP_STATUS', 'RUNNING', 'Running', 'In progress', 2),
  ('STEP_STATUS', 'SUCCEEDED', 'Succeeded', 'Done', 3),
  ('STEP_STATUS', 'SKIPPED', 'Skipped', 'Resource already existed', 4),
  ('STEP_STATUS', 'FAILED', 'Failed', 'Error; see log', 5),
  ('RECIPIENT', 'PROSPECT', 'Prospect', 'The prospect', 1),
  ('RECIPIENT', 'ED', 'Ed', 'The operator', 2),
  ('CHANNEL', 'EMAIL', 'Email', 'Email message', 1),
  ('CHANNEL', 'SMS', 'SMS', 'Text message', 2),
  ('NOTIFICATION_STATUS', 'STUBBED', 'Stubbed', 'Rendered to log only; no provider yet', 1),
  ('NOTIFICATION_STATUS', 'QUEUED', 'Queued', 'Handed to provider', 2),
  ('NOTIFICATION_STATUS', 'SENT', 'Sent', 'Provider confirmed', 3),
  ('NOTIFICATION_STATUS', 'FAILED', 'Failed', 'Provider error', 4);

-- ---------------------------------------------------------------------------
-- prospect: one row per company. A company may have many glimpses over time.
-- ---------------------------------------------------------------------------
CREATE TABLE prospect (
    id            TEXT PRIMARY KEY,                  -- uuid v4, lowercase
    company_name  TEXT NOT NULL,
    email         TEXT NOT NULL,                     -- required: Access OTP identity
    owner_name    TEXT,
    phone         TEXT,                              -- E.164, optional; SMS copies only
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    CHECK (length(trim(company_name)) > 0),
    CHECK (email = lower(email) AND instr(email, '@') > 1)
);
CREATE INDEX prospect_email_idx   ON prospect(email);
CREATE INDEX prospect_company_idx ON prospect(company_name);

-- ---------------------------------------------------------------------------
-- glimpse: one row per glimpse. One hostname; the API is served under /api/*
-- on the same host by a second Worker Route, so one Access application covers
-- both UI and API.
-- ---------------------------------------------------------------------------
CREATE TABLE glimpse (
    id                TEXT PRIMARY KEY,              -- 20-char lowercase base32
    prospect_id       TEXT NOT NULL REFERENCES prospect(id),
    state             TEXT NOT NULL,                 -- srt GLIMPSE_STATE
    hostname          TEXT NOT NULL UNIQUE,          -- <id>.glimpse.andexor.net
    ui_repo           TEXT NOT NULL UNIQUE,          -- andexor/andexor-glimpse-<id>-ui
    api_repo          TEXT NOT NULL UNIQUE,          -- andexor/andexor-glimpse-<id>-api
    ui_worker         TEXT NOT NULL UNIQUE,          -- Worker on <hostname>/*
    api_worker        TEXT NOT NULL UNIQUE,          -- Worker on <hostname>/api/*
    d1_database_id    TEXT UNIQUE,                   -- glimpse's own D1 uuid
    access_app_id     TEXT UNIQUE,                   -- the one Access application for <hostname>
    created_at        TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    notified_at       TEXT,                          -- first DRAFT -> PENDING
    activated_at      TEXT,                          -- most recent notify / reactivate / extend
    expires_at        TEXT,                          -- activated_at + 7 days
    delete_at         TEXT,                          -- activated_at + 30 days
    deleted_at        TEXT,
    extension_count   INTEGER NOT NULL DEFAULT 0,
    last_extended_at  TEXT,
    CHECK (id = lower(id) AND length(id) = 20),
    CHECK ((state IN ('PENDING','APPROVED','DECLINED','DELAYED','EXPIRED')) = (activated_at IS NOT NULL)
           OR state IN ('PROVISIONING','FAILED','DRAFT','DELETED')),
    CHECK ((state = 'DELETED') = (deleted_at IS NOT NULL))
);
CREATE INDEX glimpse_prospect_idx ON glimpse(prospect_id);
CREATE INDEX glimpse_state_idx    ON glimpse(state);
CREATE INDEX glimpse_expires_idx  ON glimpse(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX glimpse_delete_idx   ON glimpse(delete_at)  WHERE delete_at  IS NOT NULL;

-- ---------------------------------------------------------------------------
-- glimpse_event: append-only audit trail of every state transition.
-- ---------------------------------------------------------------------------
CREATE TABLE glimpse_event (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    glimpse_id   TEXT NOT NULL REFERENCES glimpse(id),
    from_state   TEXT,                               -- srt GLIMPSE_STATE; NULL on creation
    to_state     TEXT NOT NULL,                      -- srt GLIMPSE_STATE
    actor        TEXT NOT NULL,                      -- srt ACTOR
    occurred_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    detail       TEXT                                -- JSON, free-form
);
CREATE INDEX glimpse_event_glimpse_idx ON glimpse_event(glimpse_id, occurred_at);

-- ---------------------------------------------------------------------------
-- scheduled_job: one row per future expire/delete. UIs show run_at as a date;
-- cron_expression is stored here so Ed never hunts for it in the console.
-- ---------------------------------------------------------------------------
CREATE TABLE scheduled_job (
    id               TEXT PRIMARY KEY,               -- uuid v4, lowercase
    glimpse_id       TEXT NOT NULL REFERENCES glimpse(id),
    kind             TEXT NOT NULL,                  -- srt JOB_KIND
    run_at           TEXT NOT NULL,                  -- when it should fire (UTC)
    cron_expression  TEXT NOT NULL,                  -- the Worker cron that will pick it up
    status           TEXT NOT NULL DEFAULT 'PENDING',-- srt JOB_STATUS
    created_at       TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    ran_at           TEXT,
    result           TEXT                            -- JSON: outcome / error
);
CREATE INDEX scheduled_job_due_idx     ON scheduled_job(status, run_at);
CREATE INDEX scheduled_job_glimpse_idx ON scheduled_job(glimpse_id, kind);
CREATE UNIQUE INDEX scheduled_job_one_pending_idx
    ON scheduled_job(glimpse_id, kind) WHERE status = 'PENDING';

-- ---------------------------------------------------------------------------
-- provisioning_run / provisioning_step: resumable, idempotent provisioning.
-- Feeds the SSE progress stream to admin-ui.
-- ---------------------------------------------------------------------------
CREATE TABLE provisioning_run (
    id           TEXT PRIMARY KEY,                   -- uuid v4, lowercase
    glimpse_id   TEXT NOT NULL REFERENCES glimpse(id),
    kind         TEXT NOT NULL,                      -- srt RUN_KIND
    status       TEXT NOT NULL DEFAULT 'RUNNING',    -- srt RUN_STATUS
    started_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    finished_at  TEXT,
    trace_id     TEXT,                               -- Workers trace for the whole run
    error        TEXT
);
CREATE INDEX provisioning_run_glimpse_idx ON provisioning_run(glimpse_id, started_at);

CREATE TABLE provisioning_step (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id       TEXT NOT NULL REFERENCES provisioning_run(id),
    seq          INTEGER NOT NULL,
    name         TEXT NOT NULL,                      -- e.g. github.create_repo.ui
    status       TEXT NOT NULL DEFAULT 'PENDING',    -- srt STEP_STATUS
    started_at   TEXT,
    finished_at  TEXT,
    trace_id     TEXT,
    log          TEXT,                               -- JSON array of log lines
    UNIQUE (run_id, seq)
);

-- ---------------------------------------------------------------------------
-- notification: every message admin-api sends or stubs.
-- ---------------------------------------------------------------------------
CREATE TABLE notification (
    id           TEXT PRIMARY KEY,                   -- uuid v4, lowercase
    glimpse_id   TEXT REFERENCES glimpse(id),        -- NULL for system-level alerts
    recipient    TEXT NOT NULL,                      -- srt RECIPIENT
    channel      TEXT NOT NULL,                      -- srt CHANNEL
    template     TEXT NOT NULL,                      -- e.g. prospect_invite
    status       TEXT NOT NULL DEFAULT 'STUBBED',    -- srt NOTIFICATION_STATUS
    provider_id  TEXT,
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    sent_at      TEXT,
    error        TEXT
);
CREATE INDEX notification_glimpse_idx ON notification(glimpse_id, created_at);

CREATE TABLE schema_migration (
    version     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    applied_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
INSERT INTO schema_migration (version, name) VALUES (1, '0001_init');

-- ---------------------------------------------------------------------------
-- SRT enforcement triggers (generated by tools/gen_srt_triggers.py).
-- ---------------------------------------------------------------------------
CREATE TRIGGER srt_glimpse_state_ins BEFORE INSERT ON glimpse
WHEN NEW.state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse.state not in GLIMPSE_STATE'); END;
CREATE TRIGGER srt_glimpse_state_upd BEFORE UPDATE OF state ON glimpse
WHEN NEW.state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse.state not in GLIMPSE_STATE'); END;

CREATE TRIGGER srt_glimpse_event_from_state_ins BEFORE INSERT ON glimpse_event
WHEN NEW.from_state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.from_state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.from_state not in GLIMPSE_STATE'); END;
CREATE TRIGGER srt_glimpse_event_from_state_upd BEFORE UPDATE OF from_state ON glimpse_event
WHEN NEW.from_state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.from_state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.from_state not in GLIMPSE_STATE'); END;

CREATE TRIGGER srt_glimpse_event_to_state_ins BEFORE INSERT ON glimpse_event
WHEN NEW.to_state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.to_state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.to_state not in GLIMPSE_STATE'); END;
CREATE TRIGGER srt_glimpse_event_to_state_upd BEFORE UPDATE OF to_state ON glimpse_event
WHEN NEW.to_state IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='GLIMPSE_STATE' AND code=NEW.to_state AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.to_state not in GLIMPSE_STATE'); END;

CREATE TRIGGER srt_glimpse_event_actor_ins BEFORE INSERT ON glimpse_event
WHEN NEW.actor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='ACTOR' AND code=NEW.actor AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.actor not in ACTOR'); END;
CREATE TRIGGER srt_glimpse_event_actor_upd BEFORE UPDATE OF actor ON glimpse_event
WHEN NEW.actor IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='ACTOR' AND code=NEW.actor AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: glimpse_event.actor not in ACTOR'); END;

CREATE TRIGGER srt_scheduled_job_kind_ins BEFORE INSERT ON scheduled_job
WHEN NEW.kind IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='JOB_KIND' AND code=NEW.kind AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: scheduled_job.kind not in JOB_KIND'); END;
CREATE TRIGGER srt_scheduled_job_kind_upd BEFORE UPDATE OF kind ON scheduled_job
WHEN NEW.kind IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='JOB_KIND' AND code=NEW.kind AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: scheduled_job.kind not in JOB_KIND'); END;

CREATE TRIGGER srt_scheduled_job_status_ins BEFORE INSERT ON scheduled_job
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='JOB_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: scheduled_job.status not in JOB_STATUS'); END;
CREATE TRIGGER srt_scheduled_job_status_upd BEFORE UPDATE OF status ON scheduled_job
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='JOB_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: scheduled_job.status not in JOB_STATUS'); END;

CREATE TRIGGER srt_provisioning_run_kind_ins BEFORE INSERT ON provisioning_run
WHEN NEW.kind IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RUN_KIND' AND code=NEW.kind AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_run.kind not in RUN_KIND'); END;
CREATE TRIGGER srt_provisioning_run_kind_upd BEFORE UPDATE OF kind ON provisioning_run
WHEN NEW.kind IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RUN_KIND' AND code=NEW.kind AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_run.kind not in RUN_KIND'); END;

CREATE TRIGGER srt_provisioning_run_status_ins BEFORE INSERT ON provisioning_run
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RUN_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_run.status not in RUN_STATUS'); END;
CREATE TRIGGER srt_provisioning_run_status_upd BEFORE UPDATE OF status ON provisioning_run
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RUN_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_run.status not in RUN_STATUS'); END;

CREATE TRIGGER srt_provisioning_step_status_ins BEFORE INSERT ON provisioning_step
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='STEP_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_step.status not in STEP_STATUS'); END;
CREATE TRIGGER srt_provisioning_step_status_upd BEFORE UPDATE OF status ON provisioning_step
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='STEP_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: provisioning_step.status not in STEP_STATUS'); END;

CREATE TRIGGER srt_notification_recipient_ins BEFORE INSERT ON notification
WHEN NEW.recipient IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RECIPIENT' AND code=NEW.recipient AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.recipient not in RECIPIENT'); END;
CREATE TRIGGER srt_notification_recipient_upd BEFORE UPDATE OF recipient ON notification
WHEN NEW.recipient IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='RECIPIENT' AND code=NEW.recipient AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.recipient not in RECIPIENT'); END;

CREATE TRIGGER srt_notification_channel_ins BEFORE INSERT ON notification
WHEN NEW.channel IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='CHANNEL' AND code=NEW.channel AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.channel not in CHANNEL'); END;
CREATE TRIGGER srt_notification_channel_upd BEFORE UPDATE OF channel ON notification
WHEN NEW.channel IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='CHANNEL' AND code=NEW.channel AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.channel not in CHANNEL'); END;

CREATE TRIGGER srt_notification_status_ins BEFORE INSERT ON notification
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='NOTIFICATION_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.status not in NOTIFICATION_STATUS'); END;
CREATE TRIGGER srt_notification_status_upd BEFORE UPDATE OF status ON notification
WHEN NEW.status IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='NOTIFICATION_STATUS' AND code=NEW.status AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: notification.status not in NOTIFICATION_STATUS'); END;

