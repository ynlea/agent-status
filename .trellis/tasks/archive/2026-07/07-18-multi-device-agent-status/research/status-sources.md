# 状态采集调研

日期：2026-07-18

## 结论摘要

- **Codex**：优先扫本地 `~/.codex/sessions/**/rollout-*.jsonl`，按会话文件推断状态；路径 Linux/Windows 同为用户目录下 `.codex/sessions`。
- **Claude Code**：优先用 **hooks 事件流**（异步 command hook）得到红/黄/绿；transcript jsonl 可作补充展示名，不宜单独作实时状态源。
- **参考实现** `agent-status-light` 聚合为机器级计数；本产品需 **按会话输出** 多条状态。

## Codex

### 本地证据

- 本机路径示例：`/home/ynlea/.codex/sessions/2026/07/17/rollout-...jsonl`
- 行格式：`{ timestamp, type, payload }`
- 常见 `type`：`session_meta`、`event_msg`、`response_item`、`turn_context`
- `session_meta.payload` 含：`id` / `session_id`、`cwd`、`originator`（如 `codex_cli_rs` / `codex-tui`）、`source`（`cli` / `vscode`）
- 状态相关 `event_msg.payload.type` 示例：
  - `user_message` → 用户侧活动
  - `task_started` → 工作中
  - `task_complete` → 完成
  - `agent_message`、`token_count`、工具调用相关 → 活跃/工作中
- 全文中可出现 approval / permission / confirm 等词，**确认态需结合具体事件结构再精确建模**（参考实现用 pending confirmation 启发式 + 审批策略）

### 参考实现（agent-status-light）

- 根路径：`%USERPROFILE%\.codex\sessions` 或环境变量 `CODEX_STATUS_SESSIONS_ROOT`
- 扫描 `rollout-*.jsonl`，限制最近文件数与 24h 新鲜度
- 每文件推断：`pendingConfirmation` / `working`(未完成且新鲜) / `done`(完成 hold 窗口内)
- 新鲜窗口约 900s（Codex）

### 对本产品的含义

- 监控端应按 **每个 rollout 文件 = 一个会话** 上报
- 展示名可用 `cwd` 目录名 + `codex` + source 短码
- 不上报对话全文；解析时只取时间戳与类型字段即可

## Claude Code

### 本地证据

- 项目 transcript：`~/.claude/projects/<path-encoded>/<sessionId>.jsonl`
- 行类型偏 transcript（`assistant` / `user` / `permission-mode` 等），**不是**结构化 hook 事件流
- 适合：会话列表、展示名；不适合单独做可靠「等确认/工作中」实时判定

### Hooks（官方能力 + 参考实现）

- 事件：`PermissionRequest`（确认）、工作类（`UserPromptSubmit` / `PreToolUse` / `PostToolUse` 等）、完成类（`Stop` / `StopFailure` 等）
- 输入公共字段：`hook_event_name`、`session_id`、`transcript_path`、`cwd`、`permission_mode`
- 侧写建议 `async: true`，避免阻塞 Agent
- 参考实现：`AgentStatusLight.exe --claude-hook` 读 stdin JSON，写入 `data/claude-events.jsonl`，再由扫描器按 session 聚合

### 对本产品的含义

- 监控端内置 **hook 接收入口**（本地 HTTP/Unix socket 或子命令），由 Claude settings hooks 指向它
- 或监控端直接作为 hook 命令：收到事件立即上报服务端
- 按 `session_id` 维护会话状态机：confirm / working / done / idle

## 状态语义（统一）

| 状态 | 含义 | Codex 倾向信号 | Claude 倾向信号 |
|------|------|----------------|-----------------|
| `confirm` | 需用户确认/输入 | pending confirmation 启发式 | `PermissionRequest`、permission 类 Notification |
| `working` | 进行中 | task_started / 工具调用 / 未完成且新鲜 | Pre/PostToolUse、UserPromptSubmit 等 |
| `done` | 刚完成 | task_complete + hold | Stop（无后台任务时）等 |
| `idle` | 空闲/过期 | 无新鲜事件 | 会话结束/过久无事件 |

优先级（同会话）：`confirm` > `working` > `done` > `idle`

## 风险

1. Codex 确认态启发式可能漏报/误报，需实机校准
2. Claude hooks 依赖用户启用配置与 workspace trust
3. 多会话并发时上报频率要节流，避免刷爆服务端与通知
4. Windows / Linux 路径分隔与用户目录差异需抽象
