# 手机端任务改会话并优化列表样式

## Goal

轻芽 App 对用户统一使用「会话」概念（不再说「任务」），会话/设备列表中等紧凑、更贴主题；会话卡展示**持续时长**与**本会话 token 用量（如 xxM）**，数据由本任务补齐后端字段。

## Confirmed facts

- 模型已是 `Session`；设备详情文案多为「会话」；首页/欢迎页仍写「任务」。
- 共用卡 `TaskCard` 偏高（minHeight≈108）；设备卡约 94 高、装饰偏重。
- 当前 `Session` 仅有 `updated_at`，无开始时间与用量；`usage_events` 有 `session_id`，但 list 会话未汇总。
- 迁移方式：`internal/store/sqlite.go` 的 `ALTER TABLE ... ADD COLUMN` 可兼容旧库。
- 只读监控；未经用户指令不 commit / push。
- **密度**：中等紧凑（已确认）。
- **数据源**：本任务补后端字段（已确认）。

## Requirements

### R1 文案：任务 → 会话
- 用户可见文案统一「会话」：`活跃任务`→`活跃会话`，空态/气泡/欢迎页等同步。
- 不改 API 英文字段名。

### R2 会话列表 UI（中等紧凑）
- 首页与设备详情共用会话卡：减内边距/阴影/头像，间距约 8。
- 保留状态、Agent、标题、路径、设备；新增时长 + token。
- 信息层级清晰，不极简成纯文本行。

### R3 设备列表 UI（中等紧凑）
- 略降高度、弱化装饰占用；在线与活跃会话数清晰。

### R4 会话指标数据（后端 + 客户端）
- **`started_at`**：服务端首次写入该会话行时记录，后续 upsert 不覆盖；列表/WS 下发。
- **`real_usage`**：按 `machine_id+agent+session_id` 汇总 usage 真实用量（与用量页 `real_usage` 同语义），列表/WS 下发。
- 客户端展示：时长如 `23m` / `1h 12m`；用量如 `86k` / `1.2M`；无数据时 `—` 或隐藏，不瞎编。
- Memory store 同步实现，保证测试与本地模式一致。

### R5 通知使用重命名后的设备名
- App 通知正文中的设备名，必须使用用户重命名后的名称（`name_locked` 后的 `machine_name`），而不是监控端上报的主机名。
- 根因（已核实）：`ApplyReport` 给会话填 `MachineName` 时用了 `req.MachineName`；通知 payload 取自 `sess.MachineName`，故重命名后通知仍可能显示旧主机名。
- 修正：上报路径解析「有效设备名」（锁定名优先）后，写入会话 / history / notification / machine_online 等下发字段；`RenameMachine` 已更新 sessions 表的行为保留。

### R6 代码命名（默认）
- `TaskCard` / `task_card.dart` 重命名为 `SessionCard` / `session_card.dart`，引用同步。

### R7 提交
- 仅在用户明确要求时 commit / push。

## Acceptance Criteria

- [ ] App 内用户可见文案不再用「任务」指代 session。
- [ ] 会话卡 / 设备卡中等紧凑，关键信息可读可点。
- [ ] 有 `started_at` 时显示持续时长；有用量时显示 token（k/M）；无数据降级明确。
- [ ] REST/WS 会话 payload 含 `started_at`、`real_usage`；旧客户端忽略未知字段不崩。
- [ ] 设备已重命名并锁定后，状态通知里的设备名为新名称（非监控主机名）。
- [ ] 只读与状态色语义不变；相关 Go 测试与 Dart 静态核对通过（本机无 Flutter 则做符号核对）。
- [ ] 无用户指令不产生 git commit。

## Out of scope

- 会话详情页大改版
- 用量 breakdown 新增 `group_by=session`（本任务用会话快照字段，不强制改 breakdown）
- 监控端上报协议大改（时长/用量由服务端落库与聚合）
- 自动发版

## Open questions

- 无阻塞项。默认：token 用 `real_usage`；时长为「首次入库 → 现在」。

## Notes

- 复杂任务：`design.md` + `implement.md` 齐备后，经用户 review 再 `task.py start`。
