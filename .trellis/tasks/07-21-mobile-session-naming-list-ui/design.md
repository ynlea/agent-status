# Design: 会话命名 + 列表紧凑 + 时长/用量字段

## Boundaries

| 层 | 改什么 | 不改什么 |
|----|--------|----------|
| `pkg/apitypes` | `Session` 增加可选字段 | 其它 API 形状 |
| `internal/store` | sessions 表列、List/Upsert、用量聚合填入 | 用量 breakdown 分组语义 |
| `internal/server` | 透传（List/WS 已走 Session） | 新 REST 路径（非必须） |
| `mobile/` | 文案、Session 模型解析、SessionCard/设备卡 UI | 远程操作、用量页大改 |

## Contracts

### Session JSON（向后兼容）

```json
{
  "machine_id": "...",
  "agent": "claude",
  "session_id": "...",
  "display_name": "...",
  "state": "working",
  "message": "...",
  "cwd": "...",
  "updated_at": "RFC3339",
  "started_at": "RFC3339",
  "real_usage": 1234567
}
```

- `started_at`：`omitempty`；缺失时客户端不展示时长。
- `real_usage`：int64，≥0；0 可展示 `0` 或 `—`（客户端：0 且无事件时可用 `—`，有 started 无用量仍可显示 0）。
- 旧客户端忽略未知字段。

### `started_at` 语义

- 首次 `INSERT` 会话行时设为 `COALESCE(sess.UpdatedAt, now)`。
- `ON CONFLICT DO UPDATE` **不覆盖** `started_at`。
- 会话被删除后再出现 → 新 `started_at`（符合「本轮存活」）。
- 迁移：`ALTER TABLE sessions ADD COLUMN started_at TEXT`；已有行可 backfill `started_at = updated_at`（近似）。

### `real_usage` 语义

与用量页一致：

`real_usage = input + output + reasoning + cache_write + cache_hit`（`UsageMetrics.FillDerived`）。

填充时机（推荐）：

1. **读路径聚合（优先实现简单正确）**：`ListSessions` 时按当前结果集 key 批量  
   `SELECT machine_id, agent, session_id, SUM(...) FROM usage_events WHERE session_id IS NOT NULL GROUP BY ...`  
   再 merge 进 Session。  
2. **WS upsert**：在 broadcast 前同样查单会话汇总（或 list 后只对 changed 填）。  
3. Memory store：内存 map 上同样按已存 events 汇总，或维护并行计数。

若读路径在会话很多时偏慢，可后续改为 usage report 时增量更新 denormalized 列；本任务以读路径聚合为默认，便于一次做对。

### 客户端展示

- **时长**：`now - started_at` → `<1m` / `Nm` / `Nh Nm` / `Nd`。
- **用量**：`real_usage` → `<1000` 原样；`≥1e3` → `x.xk`；`≥1e6` → `x.xM`（一位小数，整数则去掉 `.0`）。
- 布局（中等紧凑 SessionCard）：
  - 左：状态 chip + Agent chip 同一行；标题一行；路径一行；底栏「设备 · 时长 · 用量 · 相对更新时间」可换行用 `·` 分隔。
  - 右：Agent 头像约 40；chevron 可选。
  - `minHeight` 约 88–96；圆角 14–16；阴影 blur 更小。
- 设备卡：高度约 78–84；右侧猫图略缩小或去掉过宽空白；文案继续「活跃会话」。

### 文案清单

| 位置 | 现 | 目标 |
|------|----|------|
| 首页标题 | 活跃任务 | 活跃会话 |
| 首页空态 | 没有活跃任务 / 新的任务 | 没有活跃会话 / 新的会话 |
| 首页气泡 | 活跃任务 | 活跃会话 |
| 欢迎页 | 跨设备任务管理 | 跨设备会话管理（或「跨设备会话监控」） |
| README | 活跃任务 | 活跃会话 |

### 重命名

- `task_card.dart` → `session_card.dart`，`TaskCard` → `SessionCard`。
- import 与测试引用同步。

## Notification device name

**现状**：`handleReport` 广播通知时用 `sess.MachineName`；`ApplyReport` 在会话 `MachineName` 为空时填 `req.MachineName`（监控主机名）。`machines` 表虽有 `name_locked` 保护重命名，但会话/通知未统一走有效名。

**目标行为**：

1. `ApplyReport`（SQLite + Memory）先得到有效名  
   `effectiveName = name_locked ? machines.machine_name : req.MachineName`  
   （与 machines upsert 的 CASE 一致）。
2. 所有本轮会话写入 / changed 列表 / history 的 `MachineName` 一律用 `effectiveName`（覆盖 monitor 自带的旧名，避免通知残留）。
3. `WSMachineOnline` 的 `MachineName` 也用有效名（避免上线事件闪旧名）。
4. `RenameMachine` 继续更新 `machines` + 该机全部 `sessions.machine_name`（已有）。
5. Android `Notifier` 已用 `payload.machineName`，服务端修对后无需改文案拼装逻辑；可顺带确认无本地缓存旧名覆盖。

**测试要点**：Rename 锁定后再次 report → changed 通知 / ListSessions 的 `machine_name` 均为新名。

## Data flow

```
monitor report sessions → Store.ApplyReport
  → effectiveName (rename lock)
  → sessions.started_at once
  → WS session + notification (machine_name = effectiveName)
monitor usage report    → usage_events
App REST/WS list        → ListSessions + real_usage → SessionCard
```

## Compatibility / rollback

- 仅新增列与 JSON 字段；回滚客户端忽略新 UI 即可，服务端多字段无害。
- 无数据迁移强依赖；`started_at` 空时 UI 降级。

## Trade-offs

| 选择 | 原因 |
|------|------|
| 读路径聚合用量 | 实现简单、与 events 一致；会话量大时再优化 denormalize |
| started_at 服务端首次见 | 不依赖 monitor 改协议；可能略晚于真实本地开始 |
| real_usage 非仅 input | 与用量页一致，用户已习惯「真实用量」 |
