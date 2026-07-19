# Database Guidelines

> SQLite for personal private deploy; short history only — not a multi-tenant product DB.

---

## Overview

Server stores:

1. **machines** — id, display name, platform, last heartbeat, online flag  
2. **sessions** — keyed by `(machine_id, agent, session_id)` with state + short display fields  
3. **history** — state transitions / done records with TTL (~24h) and max row count (~50 recent default, configurable)

No full conversation bodies. No user/account tables for multi-tenant SaaS.

---

## Technology

| Choice | Rule |
|--------|------|
| Engine | SQLite (file path from config) |
| Access | Prefer `database/sql` + small helper or a thin wrapper; avoid heavy multi-DB ORMs |
| Migrations | Simple sequential SQL files or embed schema on first open; keep forward-only for v1 |
| Concurrency | One writer discipline; use context timeouts on queries |

---

## Schema Rules

- Primary keys and uniqueness must enforce session identity `(machine_id, agent, session_id)`.
- Timestamps: store UTC; API exposes RFC3339.
- Soft fields only: `display_name`, `state`, optional short `message` (never prompt dumps).
- Indexes: heartbeat lookups, history by time, sessions by machine.

---

## Query Patterns

- **Report path:** upsert machine heartbeat + upsert each session; append history only on **state change**.
- **Query path:** read models for machines / sessions / history with `limit`.
- **Cleanup:** periodic job deletes history older than TTL or beyond max count; drop idle/done sessions past hold window.

Prefer transactions for report batches (one report payload = one unit of work).

---

## Anti-Patterns

- Storing agent chat transcripts or full prompts  
- Multi-tenant schema / role tables without product decision  
- Unbounded history growth  
- Sharing one SQLite file across multiple server processes without care  

---

## Evidence

- Product/history limits: parent `prd.md` / `design.md` §3.2, §9  
- After code: point to `internal/server/store/*` and migration files
