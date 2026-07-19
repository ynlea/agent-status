# Android 自有 App 通知调研

日期：2026-07-18

## 产品约束

- 通知必须由 **自有 Android App** 的系统通知栏展示
- 个人私有部署，支持外出访问
- 红/黄/绿均可配置；默认仅红开

## 可选投递路径

| 方案 | 优点 | 缺点 | 适配度 |
|------|------|------|--------|
| FCM（Firebase Cloud Messaging） | 系统级后台唤醒可靠；App 内直接出通知 | 需 Google 服务/账号；部分网络环境不稳；私有部署仍要持有 FCM 凭证 | 中高（有 GMS 时） |
| UnifiedPush + 自托管 distributor | 更贴私有；App 仍是通知展示方 | 用户需装/配 distributor；生态学习成本 | 中 |
| 自建长连接（WebSocket）+ 前台服务 | 完全自控；无 Google | 后台易被系统杀；费电；外出不稳定时体验差 | 前台可靠、后台弱 |
| 混合：在线 WebSocket + 离线 FCM/UnifiedPush | 体验最好 | 实现复杂度最高 | 推荐中长期 |

## 建议（首版）

**首版采用混合简化版：**

1. App 打开或后台允许时：与服务端 **WebSocket/SSE** 收实时状态与通知事件，本地弹出系统通知。
2. 为提高离线可达：预留 **FCM 设备 token** 注册接口；个人部署者可选配置 FCM 服务账号；未配置时仅依赖长连接 + 系统对 App 的后台限制说明。
3. 不把 Bark/Telegram/ntfy App 作为主入口（已 out of scope）；若将来作可选旁路再议。

## 通知事件模型（建议）

服务端在会话状态 **发生跨越**（如 idle→confirm、working→done）时生成 `NotificationEvent`：

- `device_id` / `machine_name`
- `session_id` / `agent` / `display_name`
- `from_state` / `to_state`
- `message`（短文案）
- `occurred_at`

App 按本地开关过滤后 `NotificationManager` 展示；同类会话可用同一 `notificationId` 更新，减少刷屏。

## 风险

- 无 FCM 时，国产 ROM / 省电策略可能导致漏通知 → 文档需写「加白名单 / 关闭电池优化」
- 黄灯默认关闭仍可能在用户全开时刷屏 → 服务端做最小间隔与合并
