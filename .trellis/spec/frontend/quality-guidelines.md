# Quality Guidelines (Android)

> Personal utility app: reliable reconnect, correct notifications, zero remote control.

---

## Standards

- Kotlin + Android Gradle Kotlin DSL.  
- Prefer Compose + Material 3 unless a strong reason uses Views.  
- Min SDK: choose a modern practical floor (document in module once set).  
- ProGuard/R8: keep serialization models if minify enabled.

---

## Testing

| Area | Approach |
|------|----------|
| State mapping | Unit tests for enum + priority color helpers |
| Notify filter | Unit tests: default only red fires |
| Repository merge | Unit tests with fake WS events |
| UI smoke | Optional Compose UI tests for list |

No dependency on a live private server in default CI.

---

## Forbidden Patterns

1. Remote action buttons (approve, reply, kill session)  
2. Logging the shared key or full Authorization header  
3. Using a third-party notify app as primary channel (product: this app owns notifications)  
4. Shipping iOS or web as required for v1  
5. Background work that uploads project files or transcripts  

---

## Review Checklist

- [ ] First-run config required  
- [ ] WS reconnect path exists  
- [ ] Notification toggles default correctly  
- [ ] Multi-session list does not collapse to single session  
- [ ] Matches frozen API field names  

---

## Evidence

- Child task `07-18-android-app`  
- Parent `design.md` §3.3, §7
