# Design: Claude Hook 异步与续命

## Boundaries

| 层 | 职责 |
|----|------|
| `cmd/monitor/claude_init.go` | 事件列表、handler 模板（含 `async: true`）、幂等合并 |
| `internal/monitor/claude.go` | 状态机、超时常量、`ApplyHookEvent` / `List` |
| `cmd/monitor/main.go` | `claude-hook` 入口（本轮逻辑不变） |
| `docs/deploy.md` + `configs/claude-hooks.example.json` | 文档与示例 |

不改：server、Flutter、Codex 超时语义。

## Data flow

```
Claude lifecycle event
  → settings.json command hook (async: true)
  → agent-status-monitor claude-hook (stdin JSON)
  → ApplyHookEvent → 本地 state file
  → collect + Report → 中心服务
  （Claude 主会话不等待 hook 结束）
```

## Contracts

### Hook handler shape（init 写出）

```json
{
  "type": "command",
  "command": "'/path/agent-status-monitor' claude-hook --config '/path/monitor.json'",
  "async": true
}
```

### 事件列表（目标）

`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SubagentStop`, `SessionEnd`

`SubagentStart`：仅当状态机有明确映射再加；默认不注册，避免 idle/working 抖动。

### 超时（Claude `List`）

| State | TTL without fresh UpdatedAt |
|-------|-----------------------------|
| working | 45m → idle |
| done | 10m → idle |
| confirm | 30m → idle |
| idle | 24h drop |

常量抽成包内命名常量（如 `claudeWorkingStale`），避免魔法数散落。

### 状态映射补充

| Event | State |
|-------|--------|
| PreToolUse / PostToolUse / PostToolUseFailure | working |
| SubagentStop + cancel reason | idle |
| SubagentStop 其他 | done |
| 其余保持现有 switch |

## Merge / migration

`mergeClaudeHook` 对识别为 agent-status 的 command handler：

1. 更新 `command`（若路径变化）
2. 设置 `async` 为 `true`（缺失或 false 都算需更新）
3. 新增事件缺组时 `newClaudeHookGroup` 自带 `async: true`
4. 不改动非 agent-status handler

## Trade-offs

| 选择 | 原因 |
|------|------|
| async command 而非 HTTP | 无新端口/鉴权；与现有二进制路径一致 |
| 本轮不拆 claude-hook 快速路径 | 用户选 A；async 已解决阻塞主会话 |
| working 45m 而非无限 | 仍清僵尸；比 15m 适配长任务 |
| 不做 transcript 心跳 | 范围可控，少文件扫描竞态 |

## Rollback

- 重新跑旧二进制 init 或手改 settings 去掉 `async` / 多余事件。
- 超时常量回退：改常量 + 重部署 monitor。
- state file 格式不变，无需数据迁移。

## Ops notes

- 用户需重新执行 `--init --claude`（或等价）才能拿到 async 与新事件。
- 勿用 `go run` 作为长期 hook 命令。
