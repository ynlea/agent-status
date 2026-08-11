# Design: 模型价表同步与 DB 查价

## 1. Goal & non-goals

**Goal**：`estimated_cost_usd` 的单价来自可更新的 `model_prices`，主数据源为 OpenRouter 模型列表 API，本地 override 补 cache 分项。

**Non-goals**：账单级精度、多供应商竞价、改价 UI、monitor 上报单价。

## 2. Current state

| 点 | 现状 | 问题 |
|----|------|------|
| 价表 | `internal/store/pricing.go` 的 `bundledPublicPrices` | 易过期、手改 |
| DB | `model_prices` 已建，seed `ON CONFLICT DO NOTHING` | 查询未读库 |
| 算费 | `EstimateCostUSD` → `LookupModelPrice` 扫内存 slice | 同步无效 |
| 匹配 | `NormalizeModelID` + 最长包含 | 可复用，需对接 DB |

## 3. Architecture

```text
                    ┌──────────────────────────┐
  启动 seed         │  bundled (code)          │
  override upsert   │  override (code/config)  │
                    └────────────┬─────────────┘
                                 ▼
  cron / startup ──► OpenRouter GET /api/v1/models
                                 │
                                 ▼ map + convert
                    ┌──────────────────────────┐
                    │  model_prices (SQLite)   │  ← 唯一查价真源
                    │  source: bundled|override│
                    │          |openrouter     │
                    └────────────┬─────────────┘
                                 ▼
                    EstimateCostUSD / summary
```

## 4. Data model

沿用现表，语义收紧：

| 列 | 说明 |
|----|------|
| model_id | 规范化主键（小写、无 provider 前缀、点改横线等） |
| input_per_mtok | USD / 1M |
| output_per_mtok | |
| cache_read_per_mtok | 无则 0 |
| cache_write_per_mtok | 无则 0 |
| currency | 固定 USD（MVP） |
| source | `bundled` \| `override` \| `openrouter` |
| updated_at | RFC3339 |

**写入优先级**

1. `override`：启动（及配置重载）强制 upsert，永不被 openrouter 覆盖。
2. `openrouter`：upsert 仅当目标行不存在 **或** `source IN ('bundled','openrouter')`。
3. `bundled`：仅插入缺失行（`DO NOTHING`）。

可选后续列（本任务可不加）：`alias_of`、`openrouter_id` 原始 id 日志即可。

## 5. ID normalization & matching

### 5.1 归一化（写入与查询共用）

在现有 `NormalizeModelID` 上明确规则：

1. trim、lower
2. 去掉 `provider/` 前缀（取最后一段 path）
3. 去掉 `:free` 等 suffix（`:` 后整段）
4. `.` → `-`（`claude-sonnet-4.5` → `claude-sonnet-4-5`）
5. 去掉尾部日期段 `-YYYYMMDD` / 常见 `-YYYY-MM-DD`
6. 去掉无意义尾巴如 `[1m]`

OpenRouter 写入时：对 `id` 与（若有）简称都生成同一 `model_id`；若归一后冲突，**后写 openrouter 不覆盖 override**；同 source 以更新时间或稳定排序取一（实现选「保留已有 openrouter 行并更新价格」）。

### 5.2 查询匹配顺序

1. 规范化后 exact match  
2. 静态别名表（可选，少量硬编码：`gpt-5-codex` → 与 openrouter 归一名一致）  
3. 价表内最长 prefix / contains（按 `model_id` 长度降序），避免 `claude-opus-4` 抢 `claude-opus-4-5`

### 5.3 OpenRouter 价换算

文档：`pricing.prompt` / `pricing.completion` 为 **每 token USD 字符串**。

```
input_per_mtok  = parseFloat(prompt)  * 1_000_000
output_per_mtok = parseFloat(completion) * 1_000_000
cache_*         = 0   // 由 override 补；若未来字段出现再映射
```

跳过：无法解析、价为 0 且明确 non-text、或 id 为空的项。免费模型可写入 0 价并标记 priced 命中（费用 0），或跳过让其未定价——**MVP：写入 0 价视为已定价（费用 0）**，与「有条目」一致。

## 6. Components

### 6.1 `internal/store` 价表接口

```go
type PriceStore interface {
  // 已有 Store 上扩展或内嵌
  UpsertModelPrice(p ModelPrice, source string) error
  ListModelPrices() ([]ModelPrice, error)
  LookupModelPrice(model string) (ModelPrice, bool) // 实现改为读内存缓存/DB
}
```

- SQLite：查库；进程内可 **加载全表到 map 缓存**，upsert 后 invalidate/reload，避免每次 SQL。
- Memory：map 实现同等语义。
- `EstimateCostUSD` / `ApplyCost` 调用 store 的 Lookup，而不是包级只读 slice。

注意：现 `LookupModelPrice` 是包函数。改造选项：

- **A**：`Store` 方法 + 包级函数委托「默认进程缓存」（server 注入后 set）  
- **B**：所有聚合路径改为 `s.LookupModelPrice`

选 **B 为主**：`finalizeSummary*` 已在 store 包内，直接用 receiver；测试构造 Memory/SQLite。保留包级 `NormalizeModelID` 与纯函数换算。

### 6.2 `internal/pricing` 或 `internal/store/pricesync` 同步器

- `FetchOpenRouterModels(ctx, client, baseURL, apiKey) ([]ORModel, error)`
- `MapToModelPrice(ORModel) (ModelPrice, bool)`
- `Sync(ctx, store) (inserted, updated, skipped int, err error)`

HTTP：

- URL 默认 `https://openrouter.ai/api/v1/models`
- Timeout 15–30s
- Header：`Authorization: Bearer <key>` 仅当配置了 key
- User-Agent：`agent-status-pricing/1.0`

### 6.3 配置（server）

扩展现有 server/monitor 配置风格（环境变量或 yaml，以仓库现有 config 为准）：

| 项 | 默认 | 说明 |
|----|------|------|
| `PRICING_SYNC_ENABLED` | true 或 false（实现时与 deploy 文档一致） | 是否后台同步 |
| `PRICING_SYNC_INTERVAL` | 24h | |
| `OPENROUTER_API_URL` | `https://openrouter.ai/api/v1` | |
| `OPENROUTER_API_KEY` | 空 | 可选 |
| `PRICING_SYNC_ON_START` | true | 启动先拉一次（失败不阻断 Listen） |

### 6.4 触发时机

1. 进程启动：seed bundled → upsert override → 可选异步 OpenRouter sync  
2. 定时 ticker  
3. （可选）`POST /api/v1/admin/pricing/sync` 同鉴权——**若实现成本低可做；否则仅启动+定时**

## 7. Override 内容（MVP）

至少覆盖当前 `bundledPublicPrices` 中 Claude 的 cache 分项与仍需钉死的官方列表价型号（与 2026-07 官网对齐的 Opus 4.5+ $5/$25 等）。override 负责「我们关心的准确分项」；openrouter 负责长尾覆盖。

Codex / GPT：可主要靠 openrouter + 少量 bundled；订阅制仍按 API 列表价估算（产品已声明）。

## 8. Failure & privacy

- 同步错误：log warning，保留旧表  
- 不把 API key 写入价表或日志明文  
- 不引入对话内容

## 9. Testing strategy

| 用例 | 期望 |
|------|------|
| Memory/SQLite Lookup 读 upsert 后数据 | 命中新价 |
| override 后 openrouter sync | override 行价格不变 |
| 假 HTTP 服务器返回 models JSON | 换算与 model_id 正确 |
| Normalize 样例 | `anthropic/claude-sonnet-4.5`、`claude-sonnet-4-5-20250929` 同键 |
| sync 500 | summary 仍可用 |
| EstimateCost 含 cache | override 分项计入 |

## 10. Docs

- `docs/api.md` 或 `docs/deploy.md`：价表来源、环境变量、估算声明  
- 不强制 openapi 新字段（无对外价表 CRUD 时）

## 11. Risks

| 风险 | 缓解 |
|------|------|
| OpenRouter 价 ≠ 官网 | 文档声明；override 钉关键型号 |
| id 映射漏 | 单测 + 最长匹配 + 日志 unknown model |
| 全表过大 | 个人部署可接受；缓存 map |
| 同步阻塞启动 | 异步 sync，Listen 不依赖成功 |
