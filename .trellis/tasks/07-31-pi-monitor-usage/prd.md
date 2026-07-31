# 添加 pi 监控与用量统计

## Goal

让 agent-status 监控端支持 pi(pi-coding-agent)的会话状态监控与 token 用量统计,与现有 codex / claude code 并列显示在 App 中。

## 已确认事实(2026-07-31 调查)

- pi 会话存储:`~/.pi/agent/sessions/--<工作目录路径>--/<时间戳>_<uuid>.jsonl`,每个文件 = 一个会话。
- 格式:JSONL,每行 `{"type": ...}`。第一行 header `{"type":"session","version":3,"id":"<uuid>","cwd":"/path"}`;`type:"message"` 行为会话消息,`message` 字段含 `role`(user/assistant/toolResult)、`model`、`provider`、`api`、`usage`、`timestamp`(ISO)。
- usage 结构:`{"input","output","cacheRead","cacheWrite","totalTokens","cost":{...}}`。
- **usage 语义与 claude 一致**:`input` 为每轮增量、`cacheRead`/`cacheWrite` 为本次请求量(会回落,非累计),直接取字段即可,无需 codex 的 total delta 逻辑。
- `type:"compaction"` 条目可选带 `usage`(摘要生成消耗),应计入;`toolResult` 消息的嵌套 `usage` 也可计入。
- 会话标题:优先 `type:"session_info"` 的 `name`,否则第一条 user 消息摘要。
- server 端 `internal/store/usage.go` 的 `sanitizeUsageEvent` 白名单仅允许 `claude`/`codex`,必须新增 `pi`。
- 价格走现有 OpenRouter 价表(`internal/pricing/`),无需改动。
- monitor 端 `UsageSyncer` 的 offset cursor 增量读取机制直接适用,无需 watcher。

## Requirements

1. 监控端新增 pi 用量解析:扫描 `~/.pi/agent/sessions/` 下 jsonl,提取 assistant/compaction 的 usage,按现有 UsageEvent 契约上报。
2. 监控端新增 pi 会话状态监控:扫描 pi 会话文件,推导会话列表(标题、状态、最后活动、cwd、最后 assistant 消息),与 codex/claude 合并上报。
3. server 端放行 `agent=pi` 的用量事件。
4. 移动端 App 新增 pi 的 agent 图标与显示映射。
5. 配置:新增 `pi_sessions_dir`(默认 `~/.pi/agent/sessions`),支持覆盖。

## Acceptance Criteria

- [ ] 监控端 `monitor --once` 能解析本机 pi 会话的用量事件并上报,server 端 DB 可查到 `agent=pi` 记录。
- [ ] 监控端会话上报包含 pi 会话(状态 working/idle 正确、标题非空、cwd 正确)。
- [ ] server 端 `sanitizeUsageEvent` 不再丢弃 `agent=pi` 事件。
- [ ] App 会话列表 / 用量页能显示 pi(含图标),按 agent 筛选可用。
- [ ] 增量读取正确:同一文件第二次同步不重复上报;文件追加后新事件正常上报。
- [ ] `go build ./...`、`go vet ./...`、相关单测通过(mobile 端 `flutter analyze` 通过)。

## Out of Scope

- 不做 pi extension 实时钩子(除非用户选择,见 Open Questions)。
- 不改 pricing 计价逻辑(pi 模型走 OpenRouter 价表,未收录模型显示未计价)。
- 不处理 pi 会话树分支层级(按文件聚合,时间序取最后活动)。

## Open Questions

- ~~监控方式~~:已确认采用**纯文件扫描**(定期扫描 `~/.pi/agent/sessions/`,与 codex 文件扫描一致),不做 pi extension 实时钩子。
