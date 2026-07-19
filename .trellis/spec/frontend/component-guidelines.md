# Component Guidelines (UI)

> Prefer Jetpack Compose for screens. UI is read-only status, not a control panel.

---

## Patterns

1. **Screen = state in, events out** — Composable receives UI state; side effects live in ViewModel.  
2. **Machine → sessions** — primary navigation is machines list, then sessions for one machine (or a single screen with grouped sections if simpler).  
3. **Status color** — map enum consistently:
   - `confirm` → red  
   - `working` → yellow  
   - `done` → green  
   - `idle` → muted / empty  
4. **Short labels only** — `display_name`, agent type, relative `updated_at`; never full prompts.  
5. **Connection banner** — show disconnected / reconnecting without blocking list forever.

---

## Config Screen

- Fields: server base URL, pre-shared key  
- Validate non-empty; optional connectivity probe (GET machines)  
- Save to private prefs; leave screen only when saved  

---

## List UI

- Multi-session concurrent visibility is required (product decision).  
- Prefer stable keys: `machine_id` + `agent` + `session_id`.  
- Offline machine: show last known sessions + offline indicator from heartbeat.

---

## Anti-Patterns

- Buttons that remote-approve / send input to agents  
- Hardcoding production server URLs or keys in source  
- Different color meanings on different screens  
- Rendering large free-text from server beyond short `message`

---

## Evidence

- Read-only + colors: parent `prd.md` Product Decisions  
- After code: `ui/machines/*`, `ui/sessions/*`
