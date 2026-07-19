# Async & Data Layer Guidelines

> File name kept from Trellis template (`hook-guidelines`); content is Android coroutines / data layer — not React hooks.

---

## Coroutines & Lifecycle

- ViewModels use `viewModelScope`.  
- Collect UI flows with lifecycle-aware APIs (`repeatOnLifecycle`).  
- Cancel WS when app process ends; reconnect with exponential backoff when online.

---

## Repository Pattern

`StatusRepository` (name flexible) owns:

1. REST snapshot load (machines / sessions / history if needed)  
2. WebSocket subscription for `session_upsert` / `session_remove` / `notification` / machine online events  
3. Merge into in-memory cache exposed as `StateFlow`  

UI must not open raw sockets.

---

## Networking

- Base URL + Bearer (or documented header) from prefs.  
- Timeouts on REST; ping/pong or app-level heartbeat on WS if server supports.  
- Map DTO → domain models at repository boundary.

---

## Claude/Codex “hooks” (not Android)

Server-side / monitor Claude Code hooks are **out of this layer**. Do not put hook stdin parsers in the Android app.

---

## Anti-Patterns

- Doing network I/O inside Composables  
- Multiple competing WS connections per process  
- Ignoring disconnects (silent stale UI)

---

## Evidence

- Realtime: `design.md` §4.4  
- After code: `data/ws/*`, `data/repo/*`
