# Backend Development Guidelines

> Conventions for Go server, monitor agent, and shared API types in this project.

**Stack (confirmed):** Go for Server + Monitor; SQLite for short history on server.  
**Evidence base:** Parent design `.trellis/tasks/07-18-multi-device-agent-status/design.md` (repo is greenfield; update examples once code lands).

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Repo layout for server, monitor, shared, api | Filled |
| [Database Guidelines](./database-guidelines.md) | SQLite short history, no multi-tenant ORM | Filled |
| [Error Handling](./error-handling.md) | HTTP/WS errors, auth failures, wrap/log | Filled |
| [Logging Guidelines](./logging-guidelines.md) | Levels, privacy (no prompts), fields | Filled |
| [Quality Guidelines](./quality-guidelines.md) | Tests, lint, forbidden patterns | Filled |

---

## Non-negotiables (all Go packages)

1. Pre-shared key on every protected HTTP and WebSocket path.
2. Never log or store full conversation text / prompts — whitelist fields only.
3. Session primary key: `(machine_id, agent, session_id)`.
4. State enum only: `confirm` | `working` | `done` | `idle` (priority: confirm > working > done > idle).
5. Prefer single static binaries for server and monitor (easy private deploy / cross-compile).

---

**Language**: Spec documentation is written in **English**.
