# Design: Flutter Android 后台监测与通知震动

## Approach

把旧 Kotlin 已验证的「独立进程前台服务 + 跨进程配置文件 + 本地告警」移植进 Flutter 的 Android 宿主（`mobile/android`），包名 `com.qingya.qingya`。

**不采用**纯 Dart 后台插件方案作为主路径：Flutter 引擎在划掉任务后不可靠；独立进程 `:monitor` 需要原生 Service。

`flutter_local_notifications` 本版可不作为告警主路径（可保留依赖不动）；告警与 ongoing 均由原生 `Notifier` / Service 发出，便于震动兜底与渠道控制。

## Boundaries

| 层 | 职责 |
|----|------|
| Flutter UI | 配置录入、三开关、列表展示、前台 REST/WS 刷新 |
| Flutter bridge | 保存设置时同步 `monitor_config.json` 并 start/stop Service |
| 原生 `:monitor` 进程 | 持有 WS、前台服务 ongoing、过滤开关、弹告警（声+振） |
| 服务端 | 不变；状态变化推 `notification` |

## Components to port / add（相对 `android/`）

放入 `mobile/android/app/src/main/kotlin/com/qingya/qingya/`（或 java，与现有 Flutter 宿主一致）：

1. `monitor/MonitorConfigStore` — 读/写 `filesDir` 或 `dataDir/monitor_config.json`
2. `monitor/WsClient` + 事件模型 — 连 `/api/v1/ws?key=`
3. `monitor/StatusMonitorService` — 前台服务、`START_STICKY`、`onTaskRemoved` 自启、4s 轮询配置
4. `monitor/Notifier` — 告警渠道（音+振+HIGH）与 ongoing 渠道（LOW 静音）
5. `monitor/BootReceiver` — `BOOT_COMPLETED` / `LOCKED_BOOT_COMPLETED` / `MY_PACKAGE_REPLACED`
6. `MainActivity` MethodChannel：`qingya/monitor`  
   - `syncAndStart(config)` / `stop()` / `requestPostNotifications()`

## Config contract（跨进程）

`monitor_config.json`：

```json
{
  "server_url": "https://…",
  "key": "…",
  "notify_red": true,
  "notify_yellow": true,
  "notify_green": true
}
```

映射：`notify_confirm→notify_red`，`notify_working→notify_yellow`，`notify_done→notify_green`。

Flutter `SettingsStore.save` 成功后调用 bridge；`demoMode` 或未配置时 `stop` 并写空/未配置。

> 说明：Flutter `SharedPreferences` 与独立进程不共享；必须以文件为准。

## Data flow

```
用户保存设置/开关
  → SettingsStore 写 SharedPreferences
  → MethodChannel syncAndStart
  → 原生写 monitor_config.json + startForegroundService

StatusMonitorService (:monitor)
  → 读 config → WsClient 长连
  → 收 notification → 按开关 → Notifier（通知+默认音+震动波形+Vibrator 兜底）
  → ongoing 通知刷新连接文案

Boot / 划掉任务
  → BootReceiver 或 onTaskRemoved → start Service（已配置时）
```

## Flutter 侧调整

- `main.dart` / 配置完成后：请求 `POST_NOTIFICATIONS`（API 33+），再 syncAndStart。
- `StatusRepository`：继续忽略 `notification` 弹窗（已忽略）；仅更新 UI 状态。
- 设置页可选短文案：需保留通知权限；部分机型需允许自启动（引导，不强制跳转厂商页也可先做文字说明）。
- 演示模式：不 start 服务。

## Manifest / 权限

- `INTERNET`, `POST_NOTIFICATIONS`, `VIBRATE`
- `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`
- `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`, `ACCESS_NETWORK_STATE`
- Service：`foregroundServiceType=dataSync`, `process=:monitor`, `stopWithTask=false`
- Receiver：exported + boot / package replaced

## Compatibility

- 不改服务端 API。
- 不改 Flutter 路由与 UI 结构。
- 旧 `android/` 工程仅参考，不强制删除。

## Trade-offs

| 选择 | 理由 | 代价 |
|------|------|------|
| 原生独立进程而非纯 Flutter 后台 | 划掉任务后仍能收 WS | 需维护 Kotlin 与 MethodChannel |
| 文件配置而非只靠 SharedPreferences | 跨进程可读 | 双写（prefs + json） |
| 告警只在 monitor 进程 | 避免双通知 | UI 进程单独连 WS 时不会本地弹窗（符合需求） |

## Rollback

- 关闭 Feature：不注册 Service / 不调 bridge 即可回退为前台-only。
- 渠道 ID 使用带版本后缀（如 `qingya_alert_v1`），改默认音振时 bump 版本并删旧渠道。

## Risks

- OEM 强杀 / 电池优化仍可能停服务 → 验收写“尽量”，设置页说明。
- 双进程内存与电量略增 → 可接受（个人工具）。
- 渠道创建后系统会冻结用户改过的渠道设置 → 改默认需 bump channel id。
