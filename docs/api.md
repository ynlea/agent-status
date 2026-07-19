# Agent Status API Contract (v1)

Frozen for first integration of monitor, server, and Android. Mock implementation: `cmd/mock`.

## Auth

All `/api/v1/*` routes require a pre-shared key:

- Preferred: `Authorization: Bearer <key>`
- Alternative: `X-Agent-Status-Key: <key>`
- WebSocket (debug only): `?key=<key>` query also accepted

Wrong/missing key → `401` with:

```json
{ "error": { "code": "unauthorized", "message": "invalid or missing key" } }
```

## Session state

| Value | Color | Meaning |
|-------|-------|---------|
| `confirm` | red | Needs human on the host machine |
| `working` | yellow | Agent is busy |
| `done` | green | Just finished |
| `idle` | empty | No active work |

Priority when merging: `confirm` > `working` > `done` > `idle`.

Agents: `codex` | `claude`. Platforms: `linux` | `windows`.

## REST

### `POST /api/v1/report`

Monitor push of machine heartbeat + sessions snapshot.

```json
{
  "machine_id": "uuid-or-stable-id",
  "machine_name": "desk-linux",
  "platform": "linux",
  "reported_at": "2026-07-18T12:00:00Z",
  "sessions": [
    {
      "machine_id": "uuid-or-stable-id",
      "agent": "claude",
      "session_id": "sess-1",
      "display_name": "couple-kitchen",
      "state": "confirm",
      "message": "waiting for approval",
      "updated_at": "2026-07-18T12:00:00Z"
    }
  ]
}
```

Response:

```json
{ "ok": true, "changed": 1 }
```

On **state change**, server emits WS `session_upsert` and `notification`.

### `POST /api/v1/usage/report`

Monitor batch upsert of token usage events (idempotent by `dedupe_key`, scoped with `machine_id` prefix server-side).

```json
{
  "machine_id": "uuid-or-stable-id",
  "machine_name": "desk-linux",
  "platform": "linux",
  "reported_at": "2026-07-19T12:00:00Z",
  "events": [
    {
      "dedupe_key": "claude:msg_01ABC",
      "agent": "claude",
      "model": "claude-sonnet-4-5",
      "session_id": "sess-1",
      "occurred_at": "2026-07-19T12:00:00Z",
      "input_tokens": 100,
      "output_tokens": 50,
      "reasoning_tokens": 0,
      "cache_write_tokens": 0,
      "cache_hit_tokens": 1000
    }
  ]
}
```

Notes:

- `agent`: `claude` | `codex`
- Codex `input_tokens` must already be **billed** (`raw input - cached`)
- Zero-token empty events are ignored
- Batch size max 2000

Response:

```json
{ "ok": true, "accepted": 1, "duplicates": 0 }
```

### `GET /api/v1/usage/summary`

Query:

| param | meaning |
|-------|---------|
| `from` / `to` | RFC3339 window (default last 24h if both omitted) |
| `machine_id` | optional filter |
| `agent` | optional `claude` / `codex` |
| `model` | optional exact model string |

Response metrics: `input_tokens`, `output_tokens`, `reasoning_tokens`, `cache_write_tokens`, `cache_hit_tokens`, `real_usage`, `cache_hit_rate`, `estimated_cost_usd`, `event_count`, `priced`.

- `real_usage` = input + output + reasoning + cache_write + cache_hit (volume, not invoice)
- `estimated_cost_usd` is an estimate from `model_prices` (local override + OpenRouter sync + bundled seed), not a vendor invoice

### `GET /api/v1/usage/breakdown`

Same filters as summary, plus `group_by=agent|model|machine|day` (default `model`).

```json
{
  "from": "...",
  "to": "...",
  "group_by": "model",
  "groups": [{ "key": "claude-sonnet-4-5", "input_tokens": 100, "real_usage": 1150 }]
}
```

### `GET /api/v1/machines`

```json
{
  "machines": [
    {
      "machine_id": "uuid-or-stable-id",
      "machine_name": "desk-linux",
      "platform": "linux",
      "online": true,
      "last_seen_at": "2026-07-18T12:00:00Z"
    }
  ]
}
```

### `GET /api/v1/machines/{id}/sessions`

```json
{
  "machine_id": "uuid-or-stable-id",
  "sessions": [ /* Session objects */ ]
}
```

### `GET /api/v1/history?limit=50`

Newest first. Entries record `from_state` → `to_state` transitions.

### `GET /healthz`

Unauthenticated liveness: plain `ok`.

## WebSocket

`GET /api/v1/ws` (same auth as REST). Server pushes JSON events:

```json
{ "type": "session_upsert", "payload": { /* Session */ } }
```

| type | payload |
|------|---------|
| `session_upsert` | Session |
| `session_remove` | Session identity fields (future) |
| `notification` | NotificationPayload (`state`, `color`, ids, optional `message`) |
| `machine_online` | Machine |
| `machine_offline` | Machine |
| `error` | `{ "code", "message" }` |

`notification.color`: `red` | `yellow` | `green` | `empty`.

## Privacy

Allowed fields only: ids, agent type, display name, state, short message, timestamps.  
**Do not** put conversation text or full prompts in any field or log.

`message` is preferably a **short task summary** from the latest user prompt (first line, ~48 runes).  
When no summary is available it may be a short status label (`permission request`, etc.).

## Mock server

```bash
export PATH="$HOME/.local/go/bin:$PATH"
go run ./cmd/mock -addr :8080 -key dev-secret
```

Env: `AGENT_STATUS_ADDR`, `AGENT_STATUS_KEY`.

### Example curl

```bash
KEY=dev-secret
BASE=http://127.0.0.1:8080

# report
curl -sS -X POST "$BASE/api/v1/report" \
  -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "machine_id": "m1",
    "machine_name": "desk-linux",
    "platform": "linux",
    "reported_at": "2026-07-18T12:00:00Z",
    "sessions": [{
      "agent": "claude",
      "session_id": "s1",
      "display_name": "demo",
      "state": "confirm",
      "updated_at": "2026-07-18T12:00:00Z"
    }]
  }'

# query
curl -sS -H "Authorization: Bearer $KEY" "$BASE/api/v1/machines"
curl -sS -H "Authorization: Bearer $KEY" "$BASE/api/v1/machines/m1/sessions"
curl -sS -H "Authorization: Bearer $KEY" "$BASE/api/v1/history?limit=10"
```

### Example websocat / wscat

```bash
# websocat
websocat "ws://127.0.0.1:8080/api/v1/ws" \
  -H="Authorization: Bearer dev-secret"
```

Then POST a report in another terminal; expect `session_upsert` and `notification` with `"color":"red"`.

## Shared Go types

`pkg/apitypes` — importable by mock, real server, and monitor.
