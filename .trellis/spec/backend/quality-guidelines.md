# Quality Guidelines (Go)

> Keep personal tooling simple, testable, and safe to run unattended.

---

## Code Standards

- Go modules with a single root `go.mod` unless a strong reason splits modules.  
- `gofmt` / `goimports` clean; prefer `golangci-lint` when CI is added.  
- Context: pass `context.Context` into store, HTTP client, and long loops.  
- Config via env or config file — no hardcoded shared keys.  
- Interfaces at use site for store/reporter when tests need fakes.

---

## Testing Requirements

| Area | Expectation |
|------|-------------|
| State merge / priority | Table-driven unit tests |
| Auth middleware | Reject wrong key; accept correct key |
| Report → query roundtrip | Integration test with SQLite temp file or mock store |
| History TTL / cap | Unit or integration with shortened TTL |
| Monitor parsers | Fixture jsonl / hook JSON → expected sessions |

Keep tests offline; no real Codex/Claude sessions required for CI.

Suggested commands (adjust when code exists):

```bash
go test ./...
go test ./internal/server/... -count=1
```

---

## Forbidden Patterns

1. Logging or persisting prompts / full chats  
2. Unauthenticated debug endpoints left enabled by default  
3. GUI / tray code in monitor (product decision: headless only)  
4. Coupling Android or mobile packages into Go modules  
5. Blocking the report loop forever without timeout/backoff  

---

## Review Checklist

- [ ] Shared DTO matches frozen contract  
- [ ] State enum exhaustive  
- [ ] Auth on REST + WS  
- [ ] Cleanup job exists for history  
- [ ] Cross-compile consideration for Windows monitor (build tags only if needed)  

---

## Evidence

- Acceptance ideas: child tasks `07-18-api-contract`, `07-18-server-core`, `07-18-monitor-agent`  
- Architecture: parent `design.md`
