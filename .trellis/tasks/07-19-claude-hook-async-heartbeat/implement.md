# Implement: Claude Hook 异步与续命

## Checklist

1. **超时与状态机** — `internal/monitor/claude.go`
   - [x] 抽出 `claudeWorkingStale = 45 * time.Minute` 等常量
   - [x] `List()` 中 working 使用 45m
   - [x] 确认 `PostToolUseFailure` / `SubagentStop` 分支已正确（补测试驱动微调）

2. **初始化事件与 async** — `cmd/monitor/claude_init.go`
   - [x] `claudeHookEvents` 增加 `PostToolUseFailure`、`SubagentStop`
   - [x] `newClaudeHookGroup` 增加 `"async": true`
   - [x] `mergeClaudeHook`：已存在 agent-status handler 时同步 `async: true`，计入 updated

3. **测试** — `internal/monitor/codex_test.go` / `cmd/monitor/claude_init_test.go`
   - [x] 僵尸 working：-20m 仍 working；-50m → idle
   - [x] SubagentStop cancel / 正常
   - [x] PostToolUseFailure 保持/恢复 working
   - [x] init：新装含 async；二次 init 更新旧 command 且写 async

4. **文档与示例**
   - [x] `docs/deploy.md` 事件列表 + async 说明
   - [x] `configs/claude-hooks.example.json` 对齐

5. **验证**
   - [x] `go test ./...`
   - [x] （可选）本地 `--init --claude` 检查 settings 片段

## Validation commands

```bash
go test ./internal/monitor/ ./cmd/monitor/ -count=1
go test ./... -count=1
```

## Risky points

| 点 | 注意 |
|----|------|
| 现有测试 `TestClaudeWorkingTimeoutClearsZombie` 用 -20m | 必须改阈值断言，否则失败 |
| merge 只改 type=command | 勿误改用户 http/prompt hook |
| async 后 hook 失败不可见 | 保持日志；不改变 exit 语义导致误杀 |

## Rollback points

- 仅改常量/测试：回退 commit 即可
- 已写入用户 `~/.claude/settings.json`：再跑 init 或恢复 `.agent-status.bak`

## Before start

- [x] prd / design / implement 齐
- [x] 用户审阅通过
- [x] 再执行 `task.py start`
