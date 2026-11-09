# Andexor Glimpse Main

This is the main project of a system that creates systems for creating and managing glimpses.

A glimpse is a preview of what a website could look like. It is given to a prospect who either currently has no website or has one that needs to be upgraded and modernized with a new look, more security, better performance, better accessibility, or uses AI to help their customers buy from them.

This is the **governing repository** (`andexor-glimpse-main`). It holds the master PRD, database schemas, API contracts, PlantUML diagrams, the Spec Kit constitution, and the glimpse templates. Runtime code lives in the sibling repos:

| Repo | Role |
| --- | --- |
| `andexor-glimpse-admin-ui` / `-api`  | Ed's admin app and the provisioning engine              |
| `andexor-glimpse-portal-ui` / `-api` | Prospect portal and its API                             |
| `andexor-glimpse-<id>-ui` / `-api`   | One private pair per glimpse, stamped from `templates/` |

Start with [`CLAUDE.md`](CLAUDE.md) for the standing conventions, then [`docs/PRD.md`](docs/PRD.md).

```
CLAUDE.md             conventions every Andexor repo follows; read first
docs/PRD.md           master Product Requirements Document (v1.0, 2026-11-09)
docs/diagrams/        PlantUML: components, lifecycle state machine, sequences
db/                   D1 schemas (system, portal, glimpse) + SRT conventions
api/                  OpenAPI 3.1 drafts for admin-api and portal-api
tools/                check_schemas.py, gen_srt_triggers.py
templates/            (to be added) Hello World -ui and -api glimpse templates
```
