# Error Handling

> Auth-first private API; clear HTTP/WS failures without leaking secrets or prompts.

---

## Principles

1. Fail closed on auth: missing/wrong key → `401` (or close WS).  
2. Client input errors → `400` with stable machine-readable `code` + short message.  
3. Server faults → `500`; log detail server-side, do not echo internal paths/secrets.  
4. Prefer wrapped errors (`fmt.Errorf("...: %w", err)`) at package boundaries.  
5. Never put conversation content into error messages.

---

## HTTP Mapping

| Situation | Status | Notes |
|-----------|--------|-------|
| Bad/missing shared key | 401 | Same for REST and WS upgrade |
| Invalid JSON / unknown state | 400 | Validate against enum |
| Unknown machine/session (if required) | 404 | Prefer empty lists for list endpoints when OK |
| Method not allowed | 405 | |
| Panic / unexpected store failure | 500 | Log once with request id if present |

JSON error body shape (keep stable once contract freezes):

```json
{ "error": { "code": "unauthorized", "message": "invalid key" } }
```

---

## WebSocket

- Reject upgrade without valid key.  
- On protocol error: send a close frame or a single `error` event then disconnect.  
- Do not keep half-open clients that fail auth.

---

## Monitor Agent

- Config/load failures: exit non-zero with stderr message.  
- Transient report failures: log + retry with backoff; do not crash loop on network blips.  
- Claude hook subcommand: invalid stdin → non-zero exit; never print secrets.

---

## Anti-Patterns

- Returning stack traces to clients  
- Logging Authorization headers or shared keys  
- Swallowing store errors and reporting success  

---

## Evidence

- Auth and API surface: `design.md` §4, §7  
- After code: handlers under `internal/server` and report client under `internal/monitor`
