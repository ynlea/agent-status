# State Management

> Local ViewModel state + preferences; server is source of truth for sessions.

---

## Layers

| Layer | Holds | Does not hold |
|-------|-------|---------------|
| DataStore / prefs | URL, key, notify toggles (R/Y/G) | Session list |
| Repository cache | Latest machines/sessions | Long-term history dump on disk (optional later) |
| ViewModel UI state | Loading / error / list models | Secrets in logs |

---

## UI State Shape (illustrative)

```kotlin
data class MachinesUiState(
  val loading: Boolean,
  val connected: Boolean,
  val machines: List<MachineUi>,
  val error: String? = null,
)
```

Use sealed classes for one-shot events (e.g. navigate after first config save).

---

## Notification Preferences

- Keys: notify on `confirm` / `working` / `done` (map to red/yellow/green).  
- **Defaults:** confirm=true, working=false, done=false.  
- Apply filter **before** posting a system notification.  
- Do not notify on pure `idle` transitions unless product changes.

---

## Sync Rules

- Snapshot on start + reconnect.  
- Apply WS events incrementally.  
- On auth failure: clear connected flag; prompt re-config without crashing.

---

## Anti-Patterns

- Duplicating session truth only in Compose `remember` without repository  
- Storing shared key in public SharedPreferences world-readable modes  
- Firing notifications for every WS message without state-change checks  

---

## Evidence

- Defaults and toggles: parent `prd.md`  
- After code: `data/prefs/*`, `*ViewModel.kt`
