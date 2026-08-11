# Design

## 1. real_usage 公式

`pkg/apitypes.UsageMetrics.FillDerived`：

```text
// 对齐 cc-switch derive_real_total（input 侧已是 fresh/billed）
RealUsage = InputTokens + OutputTokens + CacheWriteTokens + CacheHitTokens
// 不再 + ReasoningTokens
```

会话列表 `RealUsage` 聚合 SQL/内存同样去掉 reasoning。  
费用估算若按分项计价，reasoning 仍可按 output 价或现有逻辑（若已有则不动）。

## 2. 子会话回放去重（对齐 cc-switch）

### 识别

解析 rollout 时读 `session_meta`（可多条取最新）：

- `thread_source==subagent` 或 parent_thread_id / forked_from_id / source.subagent
- 父 thread id 字符串
- 本文件 thread id（meta.id 或文件名 UUID）

### 签名

每个 token_count 提取签名（与 cc-switch 类似，精简版）：

- total 的 input/cached/output/reasoning/total（若有）
- 和/或 last 的对应字段  
用于和父文件事件序列做前缀匹配。

### 匹配

1. 扫描时建立 `threadID → []rolloutPath`（非 subagent 优先）。
2. 子文件：加载父文件在子 `session_meta` 时间之前的 token 签名列表。
3. `matching_replay_prefix(childEvents, parentSigs)`：顺序匹配，得到前缀长度 N。
4. 解析用量时跳过前 N 个 **非零** token 事件；`prevTotal` 初始化为第 N 个事件之后的基线（第 N 个 total 快照，若存在）。

### 集成点

方案 A（推荐）：`CollectCodexUsageFiles` 仍列文件；`ParseCodexUsageFile` 增加可选 `skipPrefix int` + `startTotal`；`UsageSyncer` 在 codex 全量/发现阶段构建 parent 索引并计算 prefix。

方案 B：独立 `ParseCodexUsageFileWithParent(...)`。

增量续读：cursor 已过前缀后只需 startTotal；prefix 只在 offset=0 或首次全量时算，可写入 cursor 扩展字段 `ReplaySkip` / 已处理。

### 父缺失

记日志，**整文件仍解析**（避免丢数），不 block 同步。与 cc-switch deferred 不同（我们无复杂 pending 队列）；可后续增强。

## 3. 数据流

```text
rollouts
  → 索引 root thread
  → 每文件: meta → 若 sub: match parent prefix N
  → Parse from N with baseline
  → UsageEvent (billed in)
  → real = in+out+cw+ch
```

## 4. 兼容

- 旧 cursor 无 prefix 字段：offset>0 时不重算 prefix（已过去）。
- 重扫（rebuild-usage）从 0 开始会应用新逻辑。
