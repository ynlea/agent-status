# Design: Codex total 差分对齐 cc-switch

## Boundaries

| 层 | 职责 | 不改 |
|----|------|------|
| `internal/monitor/usage_parse.go` | Codex `token_count` → `UsageEvent` 增量语义 | Claude 解析 |
| `internal/monitor/usage_sync.go` + `fileCursor` | 持久化/传入 prev total，保证中段续读 | 上报 HTTP、服务端聚合 |
| `usage_parse_test.go` / 必要时 `usage_sync_test.go` | 钉死差分与增量 | mobile UI |

## Algorithm（对齐 cc-switch）

对每条 `event_msg` 且 `payload.type == token_count`：

```text
info = payload.info
total = info.total_token_usage
last  = info.last_token_usage

if total 存在:
    raw = delta(total, prevTotal)   // 字段：input / cached / output / reasoning
    prevTotal = total               // 即使 delta 为 0 也推进基线
    if raw 全 0: skip
else if last 存在:
    raw = last
else:
    skip

cached = min(raw.cached, raw.input)   // clamp
billed = max(raw.input - cached, 0)
emit UsageEvent{ input: billed, cache_hit: cached, output, reasoning, ... }
```

`delta`：与现有 `deltaUsageFromPrev` 同思路；某字段变小则该事件回退为「以 current 为整段」或整事件丢弃——实现时选一种并单测固定（推荐：与现函数一致，负差时返回 current 整段，避免卡死基线）。

## Incremental cursor

问题：`fromOffset > 0` 时若 `prevTotal` 为空，第一条 total 会被当成从 0 起的全量。

方案（推荐组合）：

1. **`fileCursor` 增加 Codex 基线字段**（可选 JSON，旧游标兼容）：
   - `last_total_input` / `last_total_cached` / `last_total_output` / `last_total_reasoning`（int64）
   - 或一个紧凑结构 `LastTotal map` / 定长四元组
2. `ParseCodexUsageFile` 签名扩展：传入 `startTotal`，返回 `lastTotal`（与 `LastModel` 对称）。
3. 若 `fromOffset > 0` 且 `startTotal` 为空：前缀扫描恢复最后一次 `total_token_usage`（类似 `recoverCodexModelPrefix`），再 Seek 到 offset。

截断/文件变小：现有逻辑已 reset offset；同时清空 LastTotal。

## Dedupe key

继续用 `codex:{basename}:{ts}:{totIn}+{totOut}`（基于 **累计 total** 而非 last），total 不变时不 emit，自然少脏 key。  
无 total 的 last 路径保持现有 fallback key。

服务端仍按 `dedupe_key` 幂等；算法变更后同一历史行可能 key 不变但内容不同——本任务不强制清库；若运维要校正，重置 `usage-cursors` + 换/清服务端事件（文档一句即可）。

## Data flow

```text
rollout.jsonl
  → ParseCodexUsageFile(offset, model, prevTotal)
  → []UsageEvent (billed 语义)
  → UsageSyncer 写回 cursor{offset, lastModel, lastTotal*}
  → ReportUsage → usage_events
```

## Compatibility

- 旧 `usage-cursors.json` 无 LastTotal：靠前缀恢复，多读一点前缀，行为正确。
- API / `UsageEvent` 字段不变。
- 子会话文件：仍按文件独立差分；不引入 parent 折叠。

## Risks

| 风险 | 缓解 |
|------|------|
| 中段续读丢基线 → 一次报全量 | 游标 + 前缀恢复双保险 + 单测 |
| 历史虚高数据仍在 DB | 接受；文档说明可重置游标重传 |
| total 回退/会话异常 | 沿用负差处理 + 单测 |
