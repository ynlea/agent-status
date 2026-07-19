# 技术设计：多端 Agent 状态监控系统

## 1. 目标与边界

实现个人私有的三件套：

1. **监控端**（Linux / Windows 后台）：采集 Codex + Claude 多会话状态并上报  
2. **服务端**：鉴权、汇总、短历史、向手机触达通知事件  
3. **Android App**：只读查看 + 自有系统通知  

不做：多租户 SaaS、远程操控、本机悬浮灯、iOS、第三方通知 App 主入口。

## 2. 总体架构

```text
[Codex rollout jsonl]──┐
                       ├──> [Monitor Agent] ──HTTPS/WSS──> [Server] <──WSS/HTTPS── [Android App]
[Claude hooks stdin]───┘         │                          │
                                 │ heartbeat / sessions     │ notify events
                                 └──────────────────────────┘
```

- 监控端主动推状态（push 模型），服务端不扫用户机器
- App 拉取快照 + 订阅实时流；通知由 App 本地弹出

## 3. 组件职责

### 3.1 Monitor Agent

- 启动时：服务地址 + 预共享密钥 + 机器显示名
- 采集：
  - Codex：扫描 `~/.codex/sessions/**/rollout-*.jsonl`
  - Claude：提供 `agent-status-monitor claude-hook`（或等价）供 hooks 调用；内存/本地队列合并会话状态
- 周期或事件驱动上报：`machine` 心跳 + `sessions[]` 快照（增量优先）
- 无 GUI

### 3.2 Server

- 校验预共享密钥（Header 或 query 仅限调试禁用）
- 维护：
  - machines：最后心跳、在线状态
  - sessions：按 `(machine_id, agent, session_id)` 主键
  - short history：状态变迁或完成记录，TTL ~24h 且条数上限
- 对状态变迁生成通知事件，推给已连接 App；可选 FCM 投递
- 存储首版可用 SQLite

### 3.3 Android App

- 配置：服务 URL、密钥、通知开关（红/黄/绿，默认仅红）
- 主界面：机器列表 → 会话列表（多会话同时显示，状态色）
- 实时：WebSocket；断线重连
- 通知：本 App `NotificationChannel`；按开关过滤

## 4. 核心数据契约（草案）

### 4.1 会话状态

```json
{
  "machine_id": "uuid",
  "machine_name": "desk-linux",
  "agent": "codex|claude",
  "session_id": "string",
  "display_name": "couple-kitchen",
  "state": "confirm|working|done|idle",
  "message": "optional short",
  "updated_at": "RFC3339"
}
```

### 4.2 上报

`POST /api/v1/report`

```json
{
  "machine_id": "...",
  "machine_name": "...",
  "platform": "linux|windows",
  "sessions": [ /* 当前活跃 + 短 hold 的 done */ ],
  "reported_at": "RFC3339"
}
```

鉴权：`Authorization: Bearer <shared_secret>` 或 `X-Agent-Status-Key`

### 4.3 查询

- `GET /api/v1/machines`
- `GET /api/v1/machines/{id}/sessions`
- `GET /api/v1/history?limit=`

### 4.4 实时

- `GET /api/v1/ws`（同一密钥）
- 服务端推送：`session_upsert` / `session_remove` / `notification` / `machine_online|offline`

## 5. 状态机（会话级）

```text
idle ──working事件──> working ──完成──> done ──超时──> idle
  ^                     │
  │                     └──确认事件──> confirm ──用户处理/超时──> working|idle
  └─────────────────────────────────────────────────────────────┘
```

- 同会话优先级：confirm > working > done > idle  
- 通知仅在 **状态值变化** 时触发，并受最小间隔约束  

## 6. 技术栈建议（可调整）

| 层 | 建议 | 理由 |
|----|------|------|
| Server | Go 或 Python（FastAPI）+ SQLite | 单二进制/简单部署；个人够用 |
| Monitor | Go 或 Rust 单二进制 | 易交叉编译 Linux/Windows |
| Android | Kotlin + 官方网络栈 | 系统通知与后台行为可控 |

**已确认：**

- Server + Monitor 均用 **Go**（共享 API 类型）
- Android **Kotlin**


## 7. 安全

- 全站 HTTPS（外出经反代/隧道时由反代终结 TLS）
- 预共享密钥足够个人用；密钥存服务端配置与客户端私有存储
- 上报字段白名单：禁止日志打印全文 prompt
- 不提供未鉴权的公网调试接口

## 8. 部署

- `docker compose` 一键服务端（可选）
- 监控端 systemd / Windows 服务或登录启动
- 外出：Tailscale / Cloudflare Tunnel / 反代 + HTTPS

## 9. 主要取舍

| 取舍 | 选择 | 原因 |
|------|------|------|
| 采集主动权 | 监控端推送 | 服务端不碰用户磁盘 |
| Claude 实时性 | hooks 优先 | transcript 不适合确认态 |
| 通知投递 | App 本地弹 + 实时流；FCM 可选 | 符合「自有 App 通知」且可控复杂度 |
| 存储 | SQLite 短历史 | 个人场景足够 |

## 10. 开放技术点（实现前可再校准）

1. Codex 确认态精确事件字段实机标注  
2. 是否首版就接 FCM，还是仅 WebSocket  
3. 最终语言栈确认（Go 默认）  
