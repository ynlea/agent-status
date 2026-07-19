# 监控端 Agent

## Goal

Linux / Windows 后台监控端：采集 Codex 与 Claude 多会话状态并上报服务端。

## Parent

- 父任务：`07-18-multi-device-agent-status`
- **依赖**：`07-18-api-contract`；联调优选 `07-18-server-core`（亦可用 mock）

## Requirements

- Go 单二进制；配置：server URL、密钥、machine_name
- Codex：扫描 `~/.codex/sessions/**/rollout-*.jsonl`，按会话输出状态
- Claude：`claude-hook` 子命令接收 hooks stdin，按 session 维护状态
- 变更上报 + 心跳；无 GUI / 无悬浮灯
- 上报字段：状态、session_id、agent、短展示名等；无全文

## Acceptance Criteria

- [x] 本机存在 Codex 活动时，report 中出现对应 codex 会话
- [x] 注入 Claude PermissionRequest 类 hook 后出现 confirm 会话
- [x] 多会话可同时出现在同一次 report
- [x] Linux 构建通过；Windows 交叉编译或说明可构建
- [x] 无密钥/错误地址时有清晰错误，不崩溃死循环刷屏

## Out of Scope

- 服务端实现、Android
- 本机悬浮灯
- 其他 Agent

## Dependencies

- 契约：`07-18-api-contract`
- 联调：`07-18-server-core`（推荐）或 mock
