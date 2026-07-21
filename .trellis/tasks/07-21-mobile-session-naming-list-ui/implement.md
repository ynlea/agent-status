# Implement checklist

## 0. 前置

- [ ] 用户 review 通过 `prd.md` / `design.md` / 本文件
- [ ] `python3 ./.trellis/scripts/task.py start 07-21-mobile-session-naming-list-ui`
- [ ] 提交前不 commit，除非用户明确要求

## 1. API 与存储

- [ ] `pkg/apitypes/types.go`：`Session` 增加 `StartedAt`、`RealUsage`
- [ ] `internal/store/sqlite.go`：`migrate` 增加 `started_at` 列；可选 backfill
- [ ] Upsert：INSERT 写 `started_at`；UPDATE 不覆盖
- [ ] `ApplyReport`：会话/通知/history 使用 **有效设备名**（`name_locked` 优先），不要用裸 `req.MachineName`
- [ ] `handleReport` 的 `WSMachineOnline` 使用有效设备名（若 payload 来自 store 结果则跟 store）
- [ ] `ListSessions`：选出 `started_at`；批量汇总 `real_usage` 写入
- [ ] WS/report 变更会话：填充同样字段再 broadcast
- [ ] `internal/store/memory.go`：对等行为（有效名 + started_at + real_usage）
- [ ] 测试：`started_at` 稳定、`real_usage` 汇总、**重命名后 report 通知/会话名为新名**

## 2. 客户端模型

- [ ] `mobile/lib/domain/models.dart`：`Session` 解析 `started_at`、`real_usage`
- [ ] 演示/假数据补字段（`status_repository` demo sessions）

## 3. 文案

- [ ] `home_page.dart`：活跃会话 / 空态 / 气泡
- [ ] `welcome_page.dart`
- [ ] `mobile/README.md`（可选但建议）

## 4. UI

- [ ] 重命名 `task_card.dart` → `session_card.dart`，`TaskCard` → `SessionCard`
- [ ] 中等紧凑布局 + 时长/用量格式化
- [ ] `devices_page.dart` 设备卡中等紧凑
- [ ] 首页/设备详情引用新组件名

## 5. 校验

- [ ] `go test ./pkg/apitypes/... ./internal/store/... ./internal/server/...`（或受影响包）
- [ ] Dart：本机有 flutter 则 analyze；否则符号/引用静态核对
- [ ] 手动或自检：无「活跃任务」用户文案残留（mobile/lib）

## 6. 风险点

- SQLite SELECT 列顺序变更 → Scan 字段对齐
- Memory 与 SQLite 行为分叉
- 重命名文件后遗漏 import
- 用量事件 `session_id` 为空时 real_usage 为 0（预期降级）

## Rollback

- 仅 UI：回退 mobile 提交
- 后端：新列可保留；客户端不读即旧行为
