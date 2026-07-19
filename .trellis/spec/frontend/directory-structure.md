# Directory Structure (Android)

> Kotlin Android app layout for status viewing and local notifications.

---

## Overview

Single Android application module is enough for v1. Feature packages stay flat and readable: config, list UI, realtime, notifications.

---

## Directory Layout

```text
android/                          # or app/ at repo root
└── app/
    ├── src/main/
    │   ├── AndroidManifest.xml
    │   ├── java/.../agentstatus/
    │   │   ├── MainActivity.kt
    │   │   ├── AgentStatusApp.kt
    │   │   ├── ui/
    │   │   │   ├── theme/
    │   │   │   ├── config/       # first-run URL + key
    │   │   │   ├── machines/     # machine list
    │   │   │   └── sessions/     # sessions under a machine
    │   │   ├── data/
    │   │   │   ├── api/          # REST DTOs + client
    │   │   │   ├── ws/           # WebSocket session
    │   │   │   ├── repo/         # StatusRepository
    │   │   │   └── prefs/        # DataStore: URL, key, notify flags
    │   │   ├── domain/           # State enum, pure mappers
    │   │   └── notify/           # channels, builders, filters
    │   └── res/
    └── build.gradle.kts
```

Shared API types should **mirror** the frozen contract (`api/` / `docs/api.md`), not invent alternate field names.

---

## Module Organization

| Concern | Package | Notes |
|---------|---------|--------|
| First-run setup | `ui.config` | Block main UI until URL+key present |
| Machine/session lists | `ui.machines` / `ui.sessions` | Group sessions by machine |
| Network | `data.api` / `data.ws` | Same base URL + key |
| Preferences | `data.prefs` | Encrypted/private prefs for key |
| Notifications | `notify` | Filter by user toggles before notify |

---

## Naming Conventions

- Packages: lowercase reverse-DNS + feature  
- Screens: `*Screen`, ViewModels: `*ViewModel`  
- DTOs: match server JSON field names (`snake_case` via serializer annotations)  
- Resources: `ic_state_*`, `channel_agent_status`

---

## Evidence

- Product UI scope: parent `prd.md` / `design.md` §3.3  
- After code: cite real packages under `android/app/...`
