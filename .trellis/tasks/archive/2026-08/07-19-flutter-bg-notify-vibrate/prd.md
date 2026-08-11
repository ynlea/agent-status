# Flutter 后台实时监测与通知震动

## Goal

让轻芽 Flutter App（`mobile/`）在 Android 上离开前台后仍能持续接收 Agent 状态变化，并按用户设置弹出本地通知、播放系统默认提示音并震动，解决“退到后台就断、设置了通知也不响”的问题。

## Confirmed Facts（仓库已核实）

- 主客户端是 Flutter `mobile/`（包名 `com.qingya.qingya`），依赖里有 `flutter_local_notifications`，但源码中**未实际调用**发通知。
- `StatusRepository` 仅在 App 进程存活时：WebSocket + 每 20 秒 REST 软刷新；`notification` 事件只标记已连接。
- 设置页三类开关已持久化到 `SharedPreferences`，未接到提醒链路。
- Flutter `AndroidManifest` 缺前台服务、BootReceiver、震动等权限。
- 服务端状态变化会推送 WS `session_upsert` 与 `notification`。
- 旧版 Kotlin（`android/`）已验证：独立进程 `:monitor` 前台服务 + 跨进程 `monitor_config.json` + `Notifier`（声+振）+ `BootReceiver` + `onTaskRemoved` 自拉起。

## Decisions

| 决策 | 结论 |
|------|------|
| 平台范围 | 仅 Android（本版不做 iOS） |
| 行为基准 | 对齐旧 Kotlin：前台服务 + WebSocket 后台 + 本地通知 + 震动 |
| 协议 | 复用现有 WS `notification`，不改服务端业务协议 |
| 进程恢复 | 开机自启 + 划掉任务后尽量自拉起（`START_STICKY` / `onTaskRemoved`） |
| 震动策略 | 三类状态均震动，节奏对齐旧版 `0,220,120,220`；是否提醒仅由三开关控制 |
| 告警声音 | 跟随系统默认通知音 |
| 重复通知 | 仅后台监测进程负责弹告警；Flutter UI 进程不弹同一条 `notification` |

## Requirements

1. 用户完成服务器配置且非演示模式后，自动启动 Android 后台监测服务。
2. 服务以 `dataSync` 前台服务运行，展示低打扰 ongoing 通知（连接状态文案）。
3. 收到服务端 `notification` 且对应开关开启时：弹出高优先级告警通知 + 系统默认音 + 震动；`idle` 不告警。
4. 设置页三类开关变更后，后台进程能读到新配置（跨进程配置文件）。
5. 手机重启 / 应用更新替换后，若已配置则自动恢复监测。
6. 从最近任务划掉 App 后，监测服务尽量自动拉起（受 OEM 限制时不崩溃）。
7. 前台 UI 列表实时刷新保持可用；不与后台重复弹同一条告警。
8. 清除配置或退出登录类操作时停止监测服务。

## Acceptance Criteria

- [ ] 配置服务器后出现低打扰 ongoing 通知，文案能反映连接中/已连接/重连
- [ ] App 退到后台后，触发 `confirm`/`working`/`done` 且对应开关打开：有通知、有默认提示音、有震动
- [ ] 关闭某一类开关后，该类状态不再告警
- [ ] 前台与后台同时在线时，同一事件不弹两次通知
- [ ] 重启手机后（已配置）自动恢复 ongoing 监测
- [ ] 从最近任务划掉后，服务能自拉起或至少不导致 App 崩溃；设置页可说明系统限制
- [ ] 演示模式不启动真实后台监测
- [ ] 未配置服务器时不启动有效监测连接

## Out of Scope

- iOS 后台与 APNs
- FCM 云推送
- 改服务端状态语义或 WS 协议
- 厂商自启动白名单全自动配置（最多设置页引导文案）
- 重构旧 `android/` 独立工程（仅作参考移植）

## Open Questions

- 无（产品决策已闭合；技术细节见 `design.md`）
