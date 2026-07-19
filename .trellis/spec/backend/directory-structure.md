# Directory Structure (Go)

> Target layout for Server, Monitor, shared types, and API contract artifacts.

---

## Overview

This monorepo will host three logical products under one tree:

- **server** — auth, report merge, query APIs, WebSocket fan-out, SQLite short history  
- **monitor** — Linux/Windows agent: Codex scan + Claude hook subcommand + report loop  
- **shared** — status enums, DTO, auth header helpers used by server, mock, and monitor  

Contract docs live under `docs/` or `api/` (frozen by `07-18-api-contract`).

---

## Directory Layout

```text
.
├── api/                      # OpenAPI / JSON schema (contract task)
├── docs/                     # Human-facing deploy & usage notes
├── cmd/
│   ├── server/main.go        # agent-status-server entry
│   ├── monitor/main.go       # agent-status-monitor entry
│   └── mock/main.go          # optional contract mock (or under cmd/server -tags mock)
├── internal/
│   ├── server/               # HTTP handlers, WS hub, store, cleanup
│   ├── monitor/              # scanners, hook bridge, reporter, config
│   ├── auth/                 # pre-shared key validation
│   └── config/               # env/file config loading
├── pkg/
│   └── apitypes/             # shared JSON DTOs + state enum (importable)
├── go.mod
└── docker-compose.yml        # optional private deploy
```

Adjust names only if a real package must split further; keep **cmd thin, logic in internal**.

---

## Module Organization

| Concern | Package home | Notes |
|---------|--------------|--------|
| REST + WS routes | `internal/server/http` (or `api`) | Mount under `/api/v1` |
| Session merge / notify rules | `internal/server/domain` or `service` | State priority + history TTL |
| Persistence | `internal/server/store` | SQLite implementation behind interface |
| Codex rollout scan | `internal/monitor/codex` | Read `~/.codex/sessions/**/rollout-*.jsonl` |
| Claude hooks CLI | `internal/monitor/claude` | stdin JSON → session upsert |
| Report client | `internal/monitor/report` | HTTPS client + backoff |
| Shared DTOs | `pkg/apitypes` | Used by mock + production |

Do **not** put business logic in `main.go`. Do **not** put secrets in source — load from config/env.

---

## Naming Conventions

- Packages: short, lowercase (`store`, `report`, not `serverUtils`)
- Files: snake-ish Go style is fine (`session_store.go`, `claude_hook.go`)
- Binaries: `agent-status-server`, `agent-status-monitor`
- HTTP paths: `/api/v1/...` only for product API
- Auth headers: prefer `Authorization: Bearer <key>`; optional `X-Agent-Status-Key` if documented in contract

---

## Examples (planned)

After implementation, prefer citing real paths, e.g.:

- `cmd/server/main.go` — wire config → store → HTTP server  
- `internal/server/store/sqlite.go` — machines/sessions/history  
- `internal/monitor/codex/scanner.go` — rollout → session state  
- `pkg/apitypes/session.go` — `State` enum + JSON tags  

Until code exists, treat `.trellis/tasks/07-18-multi-device-agent-status/design.md` §4 as the structural source of truth for API shapes.
