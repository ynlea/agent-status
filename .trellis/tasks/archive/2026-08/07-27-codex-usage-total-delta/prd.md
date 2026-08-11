# Codex 用量对齐 cc-switch total 差分

## Goal

把 Codex 本地用量解析改成与 cc-switch 同一套主算法：优先对 `total_token_usage` 做会话内差分；避免 `last_token_usage` 在 total 未变时被重复累加，导致统计虚高。

## Confirmed facts

- 当前 `ParseCodexUsageFile` **优先取 `last_token_usage`**，仅在 last 缺失时才对 total 做差分。
- 真实 Codex rollout 里 `token_count` 常在 total **不变**时重复带上同一份 last（等子 agent、中间态），会把同一轮用量计多次。
- 本机抽样：按 last 累加可比 total 差分虚高约 3%～30%+（文件而异）；「真实用量」含 cache 仍是另一层观感问题，本任务不改展示口径。
- cc-switch（`session_usage_codex.rs`）主路径：有 `total_token_usage` → `compute_delta(prev, current)`；无 total 才退回 last；delta 全 0 不入库。
- 上报契约不变：`input_tokens` 仍为 **billed**（raw − cache），`cache_hit_tokens` / `output` / `reasoning` 分项保留；服务端 `real_usage` 公式不动。
- 子会话文件仍各自扫描（与现网、与 cc-switch 扫全量 rollout 一致）；本任务不做主会话 token 归并。

## Product decisions

| 决策 | 结论 |
|------|------|
| 对齐范围 | 仅 Codex 会话日志解析增量算法；Claude 不变 |
| 主算法 | 优先 total 差分；无 total 才用 last |
| total 未变 | 不产生事件 |
| 增量游标 | 中段续读必须带上「上一份 total」基线，禁止把累计总量当本段 delta |
| 历史已入库数据 | 不自动改写；新解析从下一次扫描生效。可选：重置用量游标后全量重传（文档说明，不强制产品按钮） |
| 展示文案 / real_usage 含 cache | 本任务不改 |
| 子会话归并 | 本任务不改 |

## Requirements

1. `ParseCodexUsageFile` 对每条 `token_count`：
   - 有 `total_token_usage`：相对上一份 total 做差分。
   - 无 total、有 `last_token_usage`：整段采用 last（兼容旧日志）。
   - 差分后 billed/out/reason/cache 全 0：不产出事件。
2. 从 `fromOffset > 0` 增量解析时，必须恢复或传入 prev total（游标持久化 **或** 前缀扫描恢复，至少一种可靠路径），避免首条 total 被当成从 0 起的全量。
3. `cached` 不超过同条 raw input（`min(cached, rawIn)`），与 cc-switch clamp 一致。
4. 既有模型恢复（`LastModel` / 前缀 turn_context）行为保持。
5. 单测覆盖：正常 total 递增、total 不变重复 last、仅 last 无 total、增量中段续读不爆炸、多段差分 billed 正确。
6. `go test ./internal/monitor/ -count=1` 通过。

## Acceptance Criteria

- [x] 同一 `token_count` 在 total 不变、last 重复出现多次时，只计 0 次增量（不重复累加）。
- [x] 全文件 total 递增时，汇总约等于最终 total 相对起点的差分（billed/cache/out/reason 分项正确）。
- [x] 增量从文件中部 offset 续读时，不会把「截至当前的累计 total」整段再报一次。
- [x] 无 total 仅有 last 的旧样例仍能产出一条事件。
- [x] Claude 解析与上报路径无行为回归。
- [x] 相关单测通过。

## Out of scope

- 修改 `real_usage` 定义或手机「真实用量」文案。
- 子会话 token 归并到 parent。
- 服务端回填清洗历史 `usage_events`。
- 代理旁路抓包用量（cc-switch 另一路数据源）。

## Notes

调研依据：本会话对比 cc-switch `session_usage_codex.rs` 与本地 `~/.codex/sessions` 抽样。
