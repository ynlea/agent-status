# Logging Guidelines

> Structured, privacy-safe logs for personal private deploy.

---

## Levels

| Level | Use |
|-------|-----|
| Error | Auth store failures, unrecoverable report loops, migration failures |
| Warn | Repeated network retries, cleanup anomalies, degraded WS clients |
| Info | Process start/stop, config path (not secrets), listen address, successful migrations |
| Debug | Per-report session counts, state transitions (ids only) — off by default in prod |

Default runtime level: **Info**.

---

## Format

- Prefer structured logs (slog or zap-style key/value).  
- Always include: `component` (`server`|`monitor`), optional `machine_id`, `session_id`, `agent`.  
- Use RFC3339 timestamps.

Example fields:

```text
level=INFO component=server msg="report accepted" machine_id=... sessions=3
```

---

## Privacy Rules (hard)

**Never log:**

- Full prompts, conversation transcripts, tool call arguments that may contain secrets  
- Raw shared keys, full `Authorization` header values  
- Arbitrary file contents from user projects  

**Allowed:** machine_id, machine_name, agent type, session_id, display_name, state, counts, HTTP status, durations.

If a short `message` field is present on a session, treat it as already-sanitized product text; still avoid logging large free-form blobs.

---

## What to Log

| Component | Log |
|-----------|-----|
| Server | Listen bind, auth failures (without key), report accepted/rejected, cleanup runs |
| Monitor | Config loaded (server URL host only), scan errors, report success/retry |
| Hooks CLI | Event name + session_id at debug; never stdin dump of user content |

---

## Anti-Patterns

- Dumping full report payloads that may grow sensitive fields  
- Debug left on permanently in personal “prod” compose  
- Logging entire rollout jsonl lines  

---

## Evidence

- Privacy boundary: parent `prd.md` Requirements §4, `design.md` §7  
- After code: central logger setup in `cmd/*` / `internal/config`
