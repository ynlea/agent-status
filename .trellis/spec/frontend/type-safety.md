# Type Safety (Kotlin)

> Model the API enum and events explicitly; fail closed on unknown states when possible.

---

## Domain Models

- Represent session state as a sealed type or enum:

```kotlin
enum class AgentSessionState { Confirm, Working, Done, Idle }
```

- Parse API strings `confirm|working|done|idle` in one place; unknown values → treat as idle or drop with log (document choice in code).  
- Prefer kotlinx.serialization (or Moshi) with explicit field names matching contract.

---

## DTOs vs UI Models

- **DTO:** wire format, nullable where API allows.  
- **UI model:** non-null display fields with defaults (`display_name` fallback to session_id).  
- Map once in repository/mapper; UI does not parse raw JSON.

---

## Null Safety

- Key and URL: empty string is invalid config, not null crash.  
- Lists default to empty, not null.  
- Avoid `!!` except at proven non-null boundaries after validation.

---

## Events

WebSocket message `type` should be a sealed hierarchy, e.g. `SessionUpsert`, `SessionRemove`, `Notification`, `MachineOnline`, `MachineOffline`. Ignore unknown types forward-compatibly.

---

## Anti-Patterns

- Stringly-typed state colors scattered in UI (`if (state == "red")`)  
- Silent null → wrong default that looks “green” when unknown  

---

## Evidence

- Enum contract: `design.md` §4.1  
- After code: `domain/*`, `data/api/*`
