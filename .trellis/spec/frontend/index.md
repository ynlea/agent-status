# Android (Client) Development Guidelines

> Conventions for the Kotlin Android app. This layer is the product “frontend”: read-only status + system notifications.

**Stack (confirmed):** Kotlin Android app; WebSocket + REST against private server; no remote control UI.  
**Evidence base:** Parent design `.trellis/tasks/07-18-multi-device-agent-status/design.md` and child `07-18-android-app` (greenfield until code lands).

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | App modules and package layout | Filled |
| [Component Guidelines](./component-guidelines.md) | Screens / UI patterns (Compose preferred) | Filled |
| [Async & Data Layer](./hook-guidelines.md) | Coroutines, repositories, WS client (template name retained) | Filled |
| [State Management](./state-management.md) | ViewModel + UI state + notification prefs | Filled |
| [Type Safety](./type-safety.md) | Kotlin models, sealed states, serialization | Filled |
| [Quality Guidelines](./quality-guidelines.md) | Privacy, tests, forbidden UX | Filled |

---

## Non-negotiables

1. Read-only: no remote confirm/approve actions on the phone.  
2. Auth: store server URL + pre-shared key in private storage; send on REST/WS.  
3. Notifications: owned by this app (`NotificationChannel`); red/yellow/green toggles; **default only red on**.  
4. Status colors map to `confirm` (red) / `working` (yellow) / `done` (green) / `idle` (empty).  
5. Never display or store conversation transcripts.

---

**Language**: Spec documentation is written in **English**.
