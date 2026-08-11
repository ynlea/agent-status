# Design: 多端 Token 用量监控

## 1. Architecture

延续现有三端，只增加「用量」数据面，不替换会话状态监控。

```text
┌─────────────────────┐     POST /api/v1/usage/report      ┌──────────────────┐
│  monitor (本机)      │ ────────────────────────────────► │  server + SQLite │
│  Claude JSONL       │     (批量幂等事件/小时桶)            │  聚合查询 API     │
│  Codex rollout      │                                    └────────┬─────────┘
│  增量 + 兜底扫描     │                                             │
│  首次全量回填        │                                             ▼
└─────────────────────┘                              GET /api/v1/usage/summary
                                                     GET /api/v1/usage/breakdown
                                                              │
                                                              ▼
                                                     Flutter 用量 Tab
```

原则：

- 手机 **只查服务端**，不直连各电脑。
- 监控端只上报 **统计字段**，不上报对话正文。
- 会话状态 `POST /api/v1/report` 保持不变；用量用 **独立路径**，避免 snapshot 语义冲突。

## 2. Boundaries

| 组件 | 职责 | 不负责 |
|------|------|--------|
| monitor | 解析本地日志、去重、本地 cursor、批量上报、首次全量回填 | 做复杂 UI、存全局历史真源 |
| server | 鉴权、幂等入库、按设备/渠道/模型/时间聚合、价表算费 | 读用户本机磁盘 |
| mobile | 筛选展示、快捷时间范围、分设备/渠道/模型 | 解析 JSONL |

## 3. Local parse contracts

### 3.1 Claude

- 路径：`~/.claude/projects/**/*.jsonl`（含 subagents；尊重 `CLAUDE_CONFIG_DIR` 若已有配置项可扩展）
- 只处理 `type=assistant` 且含 `message.usage` 的行
- 去重：`message.id`（同 id 多行只计一次）
- 字段：
  - `input` = `usage.input_tokens`
  - `output` = `usage.output_tokens`
  - `cache_write` = `cache_creation_input_tokens` 或 `cache_creation` 拆分之和
  - `cache_hit` = `cache_read_input_tokens`
  - `reasoning` = 0
  - `model` = `message.model`
  - `at` = 行 `timestamp`

### 3.2 Codex

- 路径：`~/.codex/sessions/**/rollout-*.jsonl` + `archived_sessions`（`CODEX_HOME` 可配）
- 校验首行 `session_meta` + originator 含 codex（宽松）
- 事件：`event_msg` + `payload.type=token_count`
- 优先 `info.last_token_usage`；否则对 `total_token_usage` 做会话内差分
- 字段：
  - `input_raw` = `input_tokens`
  - `cache_hit` = `cached_input_tokens` 或 `cache_read_input_tokens`
  - `input_billed` = `max(input_raw - cache_hit, 0)`
  - `output` = `output_tokens`
  - `reasoning` = `reasoning_output_tokens`
  - `cache_write` = 0
  - `model` = 最近 `turn_context.model`
  - `at` = 事件 timestamp

### 3.3 上报归一字段（跨渠道统一）

每条 usage 事件（或合并后的原子记录）使用：

```json
{
  "dedupe_key": "claude:<message_id> | codex:<path>:<ts>:<totals...>",
  "machine_id": "...",
  "agent": "claude|codex",
  "model": "...",
  "session_id": "...",
  "occurred_at": "RFC3339",
  "input_tokens": 0,
  "output_tokens": 0,
  "reasoning_tokens": 0,
  "cache_write_tokens": 0,
  "cache_hit_tokens": 0
}
```

- Claude：`input_tokens` 直接用原生 input  
- Codex：`input_tokens` 上报 **billed**（已减 cache），`cache_hit_tokens` 单独上报  
- 服务端展示「输出」时：`output_tokens + reasoning_tokens`；明细保留 reasoning

## 4. Server data model

### 4.1 表 `usage_events`（明细，幂等）

| 列 | 说明 |
|----|------|
| dedupe_key | PRIMARY KEY（全局唯一，含 machine 前缀更稳：`{machine_id}:{key}`） |
| machine_id | |
| agent | claude / codex |
| model | |
| session_id | 可选 |
| occurred_at | UTC |
| input_tokens | 新增输入（归一后） |
| output_tokens | |
| reasoning_tokens | |
| cache_write_tokens | |
| cache_hit_tokens | |
| created_at | 入库时间 |

索引：`(machine_id, occurred_at)`、`(agent, occurred_at)`、`(model, occurred_at)`。

全量历史下事件量可能大，但个人私有场景可接受；若后续膨胀，可再加小时汇总表（MVP 可不做）。

### 4.2 表 `model_prices`（预留）

| 列 | 说明 |
|----|------|
| model_id | 规范化 id |
| input_per_mtok | USD / 1M |
| output_per_mtok | |
| cache_read_per_mtok | |
| cache_write_per_mtok | |
| currency | 默认 USD |
| source | bundled / override |
| updated_at | |

MVP：启动时从内置 JSON seed；未知模型 `estimated_cost = null` 或 0 + `priced=false`。

### 4.3 聚合公式（服务端）

```
fresh_input   = sum(input_tokens)
output_total  = sum(output_tokens + reasoning_tokens)
cache_hit     = sum(cache_hit_tokens)
cache_write   = sum(cache_write_tokens)
real_usage    = fresh_input + output_total + cache_hit + cache_write
hit_rate      = cache_hit / (cache_hit + cache_write + fresh_input)  // 分母0 → null
est_cost      = Σ 分项单价 * token / 1e6
```

## 5. API contracts

鉴权同现有 Bearer / `X-Agent-Status-Key`。

### 5.1 `POST /api/v1/usage/report`

```json
{
  "machine_id": "uuid",
  "machine_name": "desk-linux",
  "platform": "linux",
  "reported_at": "...",
  "events": [ /* UsageEvent 批量，建议 ≤500/次 */ ]
}
```

响应：`{ "ok": true, "accepted": N, "duplicates": M }`  
语义：按 `dedupe_key` UPSERT/IGNORE，全量回填可重放。

（可选）顺带 touch machine online，与状态 report 一致。

### 5.2 `GET /api/v1/usage/summary`

Query：

- `from` / `to`（RFC3339，必填其一策略：无则默认今天本地日界 → 服务端用 UTC 或 query `tz`；MVP 用客户端算好 UTC 窗口）
- `machine_id` 可选
- `agent` 可选 `claude|codex`
- `model` 可选

响应：

```json
{
  "from": "...", "to": "...",
  "real_usage": 0,
  "input_tokens": 0,
  "output_tokens": 0,
  "reasoning_tokens": 0,
  "cache_hit_tokens": 0,
  "cache_write_tokens": 0,
  "cache_hit_rate": 0.0,
  "estimated_cost_usd": 0.0,
  "event_count": 0
}
```

### 5.3 `GET /api/v1/usage/breakdown`

同样过滤参数 + `group_by=agent|model|machine|day`

响应：`{ "groups": [ { "key": "...", ...metrics } ] }`

### 5.4 快捷范围

由 **手机/客户端** 换算为 `from`/`to`：

| 快捷 | 含义 |
|------|------|
| today | 本地日 00:00 → now |
| 1d | now-24h → now |
| 7d | now-7d → now |
| 30d | now-30d → now |
| custom | 用户选 |

服务端只认绝对时间窗，避免时区歧义堆在服务端。

### 5.5 WebSocket

MVP **不推**用量增量；手机下拉刷新 / 进入页拉取即可。状态 WS 不变。

## 6. Monitor runtime

1. **Cursor 状态**：`~/.agent-status/usage-cursors.json`（路径可配）  
   - 每文件：offset / 指纹 / 已处理 dedupe 窗口  
2. **首次启动**：若无 `usage_backfill_done` 标记 → 后台全量扫描所有 Claude/Codex 日志 → 分批 POST → 成功后打标  
3. **日常**：  
   - fsnotify / 现有 watcher 风格：文件 append 时增量  
   - 每 10 分钟（可配 5–15）兜底 walk  
4. **与状态循环并行**：用量失败不阻断 session report  

## 7. Mobile UX

- 主导航增加 **用量** Tab（或从首页入口进入二级页；推荐 Tab，路径 `/usage`）
- Hero 卡：真实用量、估算费用、缓存命中率、事件数  
- 筛选条：时间快捷、设备、渠道  
- 列表：按模型 / 按渠道 breakdown  
- 模型行可展开：output vs reasoning、cache 分项  
- 文案：「估算费用，非账单」

## 8. Compatibility & privacy

- 旧客户端忽略新 API；旧服务端无路由时 monitor 记录错误并退避  
- SQLite migrate 追加新表，不破坏 machines/sessions/history  
- 禁止：prompt、assistant 正文、tool 参数写入 usage API  

## 9. Trade-offs

| 选择 | 利 | 弊 |
|------|----|----|
| 独立 usage report | 不污染 session snapshot | 多一条上报通道 |
| 事件级存储 | 任意范围聚合准 | 全量历史库变大 |
| 内置价表 | 简单可控 | 需发版更新价格 |
| 无 WS 用量推送 | 实现简单 | 非秒级实时 |

## 10. Rollback

- 特性开关：`monitor.json` → `usage_enabled: false`  
- 服务端保留表无害；可停路由  
- 手机隐藏用量入口 feature flag（可选）  
