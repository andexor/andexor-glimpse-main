#!/usr/bin/env python3
"""Load each db/*/0001_init.sql into an in-memory SQLite database and run
constraint smoke tests. Exit non-zero on any failure. Run from repo root."""
import sqlite3, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
failures = 0

def load(name):
    con = sqlite3.connect(":memory:")
    con.execute("PRAGMA foreign_keys=ON")
    con.executescript((ROOT / "db" / name / "0001_init.sql").read_text())
    return con

def expect(con, sql, should_fail, label):
    global failures
    try:
        con.execute(sql); failed = False
    except Exception:
        failed = True
    ok = failed == should_fail
    failures += 0 if ok else 1
    print(f"  [{'PASS' if ok else 'FAIL'}] {label}")

for name in ("system", "portal", "glimpse"):
    con = load(name)
    trig = con.execute("select count(*) from sqlite_master where type='trigger'").fetchone()[0]
    print(f"{name}: loaded, {trig} triggers")

s = load("system")
s.execute("INSERT INTO prospect(id,company_name,email) VALUES('p1','Acme','ed@acme.com')")
cols = "(id,prospect_id,state,hostname,ui_repo,api_repo,ui_worker,api_worker)"
expect(s, f"INSERT INTO glimpse{cols} VALUES('Q7MX2K9PBD4HT6WZ3NRA','p1','PROVISIONING','h','r','ra','w','wa')", True, "uppercase glimpse id rejected")
expect(s, f"INSERT INTO glimpse{cols} VALUES('q7mx2k9pbd4ht6wz3nra','p1','provisioning','h','r','ra','w','wa')", True, "lowercase state rejected (SRT)")
expect(s, f"INSERT INTO glimpse{cols} VALUES('q7mx2k9pbd4ht6wz3nra','p1','LIVE','h','r','ra','w','wa')", True, "LIVE rejected (not in SRT)")
expect(s, f"INSERT INTO glimpse{cols} VALUES('q7mx2k9pbd4ht6wz3nra','p1','PROVISIONING','h','r','ra','w','wa')", False, "PROVISIONING accepted")
expect(s, "UPDATE glimpse SET state='PENDING' WHERE id='q7mx2k9pbd4ht6wz3nra'", True, "PENDING without activated_at rejected")
expect(s, "UPDATE glimpse SET state='PENDING', activated_at='t', notified_at='t', expires_at='t', delete_at='t' WHERE id='q7mx2k9pbd4ht6wz3nra'", False, "PENDING with activated_at accepted")
expect(s, "INSERT INTO glimpse_event(glimpse_id,to_state,actor) VALUES('q7mx2k9pbd4ht6wz3nra','PENDING','ed')", True, "lowercase actor rejected (SRT)")
expect(s, "INSERT INTO scheduled_job(id,glimpse_id,kind,run_at,cron_expression) VALUES('j1','q7mx2k9pbd4ht6wz3nra','EXPIRE','t','0 * * * *')", False, "EXPIRE job accepted")
expect(s, "INSERT INTO scheduled_job(id,glimpse_id,kind,run_at,cron_expression) VALUES('j2','q7mx2k9pbd4ht6wz3nra','EXPIRE','t','0 * * * *')", True, "second PENDING EXPIRE rejected")
expect(s, "INSERT INTO glimpse_event(glimpse_id,to_state,actor) VALUES('nope','PENDING','ED')", True, "FK to unknown glimpse rejected")

p = load("portal")
p.execute("INSERT INTO prospect(id,company_name,email) VALUES('p1','Acme','ed@acme.com')")
p.execute("INSERT INTO glimpse(id,prospect_id,company_name,hostname,expires_at) VALUES('q7mx2k9pbd4ht6wz3nra','p1','Acme','h','t')")
expect(p, "INSERT INTO decision_log(prospect_id,glimpse_id,action) VALUES('p1','q7mx2k9pbd4ht6wz3nra','APPROVE')", True, "APPROVE rejected (SRT)")
expect(p, "INSERT INTO decision_log(prospect_id,glimpse_id,action) VALUES('p1','q7mx2k9pbd4ht6wz3nra','DECLINED')", False, "DECLINED accepted")
expect(p, "INSERT INTO decision_log(prospect_id,glimpse_id,action) VALUES('p1','q7mx2k9pbd4ht6wz3nra','DELAYED')", True, "DELAYED without new_expires_at rejected")
expect(p, "INSERT INTO decision_log(prospect_id,glimpse_id,action,new_expires_at) VALUES('p1','q7mx2k9pbd4ht6wz3nra','DELAYED','t2')", False, "DELAYED with new_expires_at accepted")
expect(p, "INSERT INTO decision_log(prospect_id,glimpse_id,action) VALUES('p1','q7mx2k9pbd4ht6wz3nra','APPROVED')", False, "APPROVED accepted")
cur = p.execute("select decision from glimpse_current_decision").fetchone()[0]
print(f"  [{'PASS' if cur=='APPROVED' else 'FAIL'}] current decision view = {cur}")
failures += 0 if cur == "APPROVED" else 1
expect(p, "INSERT INTO comment(glimpse_id,prospect_id,author,body) VALUES('q7mx2k9pbd4ht6wz3nra','p1','prospect','hi')", True, "lowercase author rejected (SRT)")
expect(p, "INSERT INTO comment(glimpse_id,prospect_id,author,body) VALUES('q7mx2k9pbd4ht6wz3nra','p1','PROSPECT','hi')", False, "PROSPECT author accepted")

print("ALL PASS" if failures == 0 else f"{failures} FAILURE(S)")
sys.exit(1 if failures else 0)
