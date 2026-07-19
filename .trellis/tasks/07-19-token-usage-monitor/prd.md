# Token 用量：监控端解析上报

## Goal

监控端从本机 Claude / Codex 日志解析 token，首次全量回填、之后增量上报服务端，且不阻断现有会话状态上报。

## Parent

`07-19-multi-device-token-usage` — 解析口径与上报字段以父任务 `design.md` 为准。

## Dependencies

**依赖** `07-19-token-usage-server` 的 API 可用（或本地先起带 usage 路由的 server）。

## Requirements

- Claude JSONL：message.id 去重，usage 分项
- Codex rollout：token_count；input 上报 billed；cache/reasoning 分项
- 首次全量回填 + cursor 续传 + 分批 POST `/api/v1/usage/report`
- 文件变更增量 + 5–15 分钟兜底
- `usage_enabled` 配置；失败退避
- 不上报对话正文

## Acceptance Criteria

- [x] `go test ./internal/monitor` 覆盖两边样例
- [ ] 本机跑 monitor 后服务端出现今日/历史用量（需对接运行中的 server）
- [x] 重跑不重复计数（服务端 dedupe + 本地 cursor）
- [x] 关闭 usage 后 session report 仍正常（`usage_enabled: false`）

## Status

核心解析与同步循环已实现（2026-07-19）。可对现有 `monitor.json` 的 server 做一次 `--once` 联调。
