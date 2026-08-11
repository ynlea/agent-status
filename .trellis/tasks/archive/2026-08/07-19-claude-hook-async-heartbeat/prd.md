# Claude Hook 状态续命与异步上报优化

## Goal

让 Claude Code 长任务在监控里更稳地保持 `working`，并减少 hook 同步阻塞；手机端仍能及时看到确认 / 工作中 / 完成 / 空闲。

## Confirmed facts

- 初始化注册：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PermissionRequest`、`Notification`、`Stop`、`StopFailure`、`SessionEnd`。
- 状态机已识别未注册：`SubagentStop`、`PostToolUseFailure`。
- 当前过期：Claude `done` 10m、`working` 15m、`confirm` 30m；Codex `working` 约 5m。
- `claude-hook` 同步写状态并 HTTP 上报。
- Claude Code command hook 支持 `"async": true`（不阻塞主会话；不可再做 decision 拦截，本项目本就不拦截）。

## Scope（已确认）

全部做，单任务不拆子任务：

1. 补 hook + 拉长 `working` 超时（方案 A，不做 transcript 心跳）
2. command hook 配置 `"async": true`（方案 A，不做 HTTP hook、本轮不做命令内提速改造）
3. `claude-init` / 文档 / 测试同步

## Requirements

### R1 补全 hook 覆盖

- 初始化事件列表增加：`SubagentStop`、`PostToolUseFailure`。
- 若代码路径可安全处理 `SubagentStart` 则注册；否则仅文档说明不纳入。
- 状态语义不变：confirm > working > done > idle。
- 工具/子 agent 相关事件刷新 `working` 与 `UpdatedAt`。

### R2 长任务续命

- Claude 超时（无新 hook 刷新 `UpdatedAt`）：
  - `working`：**45 分钟** → idle
  - `done`：10 分钟 → idle
  - `confirm`：30 分钟 → idle
- 不做 transcript 扫描心跳。
- Codex 超时策略本轮不改。

### R3 异步上报

- `claude-init` 写入的 agent-status command hook 一律带 `"async": true`。
- 幂等更新：已存在的 agent-status hook 若缺 `async` 或 `async: false`，更新为 `true`；同步更新 `command` 路径。
- `claude-hook` 处理逻辑本轮保持：落盘 + collect + report（依赖 Claude 侧 async 不挡主会话）。
- 不上 HTTP hook 端点。

### R4 兼容与文档

- 不删除用户其他 hook。
- 更新 `docs/deploy.md`、`configs/claude-hooks.example.json` 事件列表与 async 说明。
- 测试覆盖超时与 init 合并行为。

## Acceptance Criteria

- [ ] `claudeHookEvents` 含 `SubagentStop`、`PostToolUseFailure`；init 可重复执行不破坏他人 hook
- [ ] init 写出的 agent-status handler 含 `"async": true`；二次 init 仍保持 true
- [ ] Claude `working`：15 分钟内仍 working；超过 45 分钟无刷新 → idle（单测）
- [ ] `SubagentStop` 非取消 → done；取消原因 → idle（与 Stop 规则一致，单测）
- [ ] `PostToolUseFailure` → working 续命（单测）
- [ ] `go test ./...` 通过
- [ ] deploy / 示例配置与实现一致

## Out of scope

- transcript 心跳扫描
- HTTP hook / monitor 本地监听端口
- claude-hook 内部分阶段快速返回 / 后台上报重构
- Codex 超时改造
- 可观测性看板、Flutter/服务端大改

## Open questions

（无，产品决策已收口）

## Notes

- 实现前需用户审过 `design.md` / `implement.md` 再 `task.py start`。
