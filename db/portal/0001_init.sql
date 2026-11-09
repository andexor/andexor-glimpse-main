-- andexor-glimpse-portal-api — portal database
-- Owner: portal-api only. The only home for prospect feedback text.
-- Dialect: SQLite (Cloudflare D1). Migration 0001.
--
-- Not here, by design: provisioning data, repo names, Access ids, scheduled
-- jobs, tokens, or anything about glimpses this prospect does not own.
-- admin-api writes the glimpse record (upsert_glimpse) and reads feedback on
-- demand (get_feedback). portal-api calls admin-api for extend and
-- record_decision. Nothing is replicated beyond the glimpse record below.
-- Finite-value fields hold UPPERCASE codes from srt, enforced by triggers.

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
  ('DECISION_ACTION', 'APPROVED', 'Approved', 'Prospect approved the design', 1),
  ('DECISION_ACTION', 'DECLINED', 'Declined', 'Prospect declined the design', 2),
  ('DECISION_ACTION', 'DELAYED', 'Delayed', 'Prospect asked for more time', 3),
  ('AUTHOR', 'PROSPECT', 'Prospect', 'The prospect', 1),
  ('AUTHOR', 'ED', 'Ed', 'The operator', 2),
  ('RECIPIENT', 'PROSPECT', 'Prospect', 'The prospect', 1),
  ('RECIPIENT', 'ED', 'Ed', 'The operator', 2),
  ('CHANNEL', 'EMAIL', 'Email', 'Email message', 1),
  ('CHANNEL', 'SMS', 'SMS', 'Text message', 2),
  ('NOTIFICATION_STATUS', 'STUBBED', 'Stubbed', 'Rendered to log only; no provider yet', 1),
  ('NOTIFICATION_STATUS', 'QUEUED', 'Queued', 'Handed to provider', 2),
  ('NOTIFICATION_STATUS', 'SENT', 'Sent', 'Provider confirmed', 3),
  ('NOTIFICATION_STATUS', 'FAILED', 'Failed', 'Provider error', 4);

CREATE TABLE prospect (
    id            TEXT PRIMARY KEY,                  -- same uuid as system db
    company_name  TEXT NOT NULL,
    email         TEXT NOT NULL UNIQUE,              -- lowercase; Access OTP identity
    created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    CHECK (email = lower(email) AND instr(email, '@') > 1)
);

-- The fields the prospect needs, written by admin-api at notify / reactivate /
-- extend / expire / delete.
CREATE TABLE glimpse (
    id             TEXT PRIMARY KEY,                 -- 20-char lowercase base32
    prospect_id    TEXT NOT NULL REFERENCES prospect(id),
    company_name   TEXT NOT NULL,
    hostname       TEXT NOT NULL UNIQUE,             -- <id>.glimpse.andexor.net
    expires_at     TEXT NOT NULL,
    active         INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0,1)),
    deleted        INTEGER NOT NULL DEFAULT 0 CHECK (deleted IN (0,1)),
    created_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    updated_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    CHECK (id = lower(id) AND length(id) = 20)
);
CREATE INDEX glimpse_prospect_idx ON glimpse(prospect_id);

-- Append-only. Every press of Approve, Decline, or "I need more time" adds a
-- row. A glimpse's current decision is its latest APPROVED/DECLINED row.
CREATE TABLE decision_log (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    prospect_id     TEXT NOT NULL REFERENCES prospect(id),
    glimpse_id      TEXT NOT NULL REFERENCES glimpse(id),
    action          TEXT NOT NULL,                   -- srt DECISION_ACTION
    occurred_at     TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now')),
    new_expires_at  TEXT,                            -- DELAYED rows only
    CHECK ((action = 'DELAYED') = (new_expires_at IS NOT NULL))
);
CREATE INDEX decision_log_glimpse_idx  ON decision_log(glimpse_id, occurred_at);
CREATE INDEX decision_log_prospect_idx ON decision_log(prospect_id, occurred_at);

CREATE VIEW glimpse_current_decision AS
SELECT d.glimpse_id, d.action AS decision, d.occurred_at AS decided_at
FROM decision_log d
JOIN (SELECT glimpse_id, MAX(id) AS max_id FROM decision_log
      WHERE action IN ('APPROVED','DECLINED') GROUP BY glimpse_id) latest
  ON latest.max_id = d.id;

CREATE TABLE comment (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    glimpse_id   TEXT NOT NULL REFERENCES glimpse(id),
    prospect_id  TEXT NOT NULL REFERENCES prospect(id),
    author       TEXT NOT NULL,                      -- srt AUTHOR
    body         TEXT NOT NULL CHECK (length(trim(body)) > 0),
    created_at   TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ','now'))
);
CREATE INDEX comment_glimpse_idx ON comment(glimpse_id, created_at);

CREATE TABLE notification (
    id           TEXT PRIMARY KEY,                   -- uuid v4, lowercase
    glimpse_id   TEXT NOT NULL REFERENCES glimpse(id),
    recipient    TEXT NOT NULL,                      -- srt RECIPIENT
    channel      TEXT NOT NULL,                      -- srt CHANNEL
    template     TEXT NOT NULL,
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

-- SRT enforcement triggers (generated by tools/gen_srt_triggers.py).
CREATE TRIGGER srt_decision_log_action_ins BEFORE INSERT ON decision_log
WHEN NEW.action IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='DECISION_ACTION' AND code=NEW.action AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: decision_log.action not in DECISION_ACTION'); END;
CREATE TRIGGER srt_decision_log_action_upd BEFORE UPDATE OF action ON decision_log
WHEN NEW.action IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='DECISION_ACTION' AND code=NEW.action AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: decision_log.action not in DECISION_ACTION'); END;

CREATE TRIGGER srt_comment_author_ins BEFORE INSERT ON comment
WHEN NEW.author IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='AUTHOR' AND code=NEW.author AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: comment.author not in AUTHOR'); END;
CREATE TRIGGER srt_comment_author_upd BEFORE UPDATE OF author ON comment
WHEN NEW.author IS NOT NULL AND NOT EXISTS (SELECT 1 FROM srt WHERE domain='AUTHOR' AND code=NEW.author AND active=1)
BEGIN SELECT RAISE(ABORT, 'SRT violation: comment.author not in AUTHOR'); END;

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

