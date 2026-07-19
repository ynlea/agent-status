# 模型价表：OpenRouter 同步 + 本地 override + DB 查价

## Goal

让服务端用量费用估算有一个**稳定、可自动更新、覆盖面够用**的价表来源：以 OpenRouter 公开模型列表为主同步源，本地 override 补分项（尤其 Claude cache），`model_prices` 为唯一查价真源。

## Parent

`07-19-multi-device-token-usage` — 估算费用口径与父任务一致：分项单价 × token，标注「估算非账单」；未知模型不 500。

## Dependencies

- 依赖已有 `usage_events` 聚合与 `EstimateCostUSD` 调用链（`07-19-token-usage-server` 已落地骨架）。
- 不依赖 monitor / mobile 改版；手机继续读 summary/breakdown 里的 `estimated_cost_usd` / `priced` 即可。

## User value

- Claude / Codex 常见型号自动有价，少手工改 Go 常量。
- 新模型出现后，同步后即可参与估算。
- 网络/同步失败时仍能用上次价表算费，不拖垮用量接口。

## Requirements

### R1 查价真源

1. 费用估算**只**从可持久化价表读取（SQLite `model_prices`；Memory store 等价内存表）。
2. 代码内置价表仅作 **cold seed / 离线兜底**，不得在查询路径绕过 DB。
3. 分项：`input / output / cache_read / cache_write`（USD / 1M tokens），与现有 `ModelPrice` / `EstimateCostUSD` 一致。
4. 未知模型：`priced=false`，`estimated_cost_usd` 可为 null 或仅含已定价分模型之和（与现行为兼容）。

### R2 OpenRouter 同步

1. 从 OpenRouter 公开接口拉取模型列表（`GET https://openrouter.ai/api/v1/models`）。
2. 解析各模型 `pricing.prompt` / `pricing.completion`（按 token 计价字符串 → 换算为 USD / 1M）。
3. 将 OpenRouter id（如 `anthropic/claude-sonnet-4.5`）归一到与本地日志兼容的 `model_id`（与现有 `NormalizeModelID` 体系对齐并可扩展别名）。
4. 同步结果 upsert 到 `model_prices`，`source=openrouter`。
5. **不得**覆盖 `source=override` 的行。
6. 同步可配置：开关、间隔、可选 API key（列表接口优先无 key；有 key 则带上）、超时。
7. 失败只记日志/指标，**不影响** usage report / summary / breakdown 可用性。

### R3 本地 override 与 bundled seed

1. 维护本地 override 列表（代码或配置均可，MVP 可用内置表），含 Claude 等 **cache_read / cache_write** 准确分项；`source=override`，优先于 openrouter/bundled。
2. 启动时 seed：bundled 仅 `ON CONFLICT DO NOTHING` 或「仅当行不存在」；override 启动时强制 upsert。
3. 允许后续用配置文件扩展 override（接口预留即可，MVP 可不做 HTTP 改价 UI）。

### R4 模型匹配

1. 日志常见形态：`claude-sonnet-4-5-20250929`、`claude-opus-4-7`、`gpt-5.4`、`gpt-5-codex` 等须能命中。
2. 匹配顺序建议：精确 → 规范化 id → 别名表 → 最长前缀/包含（与现逻辑类似，但数据来自价表）。
3. 不要求覆盖「世上所有模型」；优先用量事件里会出现的 Claude/Codex 相关型号 + OpenRouter 同步到的集合。

### R5 运维与可观测

1. 提供手动触发同步的方式之一即可：服务启动时可选同步、后台定时、或管理/内部命令/HTTP（若加 HTTP，须鉴权与现网 key 一致）。
2. 能查看最近同步时间与结果（日志足够；可选简单 status 字段，非必须 API）。
3. 文档说明：费用为估算；OpenRouter 挂牌价可能与官网列表价有差异。

## Out of scope

- 与供应商发票自动对账
- 用户自定义改价 UI
- 手机端改价展示文案大改（沿用「估算」即可）
- 为计价真实调用 chat completions
- 引入第二定价供应商（LiteLLM 等）作为主路径

## Acceptance Criteria

- [ ] `Lookup`/`EstimateCostUSD` 从 store 价表读取，单测不依赖「只能看到代码常量」
- [ ] 模拟 OpenRouter 响应可 upsert 价表；`override` 行不被 openrouter 覆盖
- [ ] Claude 带 cache 分项的 override 生效，费用含 cache 分量
- [ ] 同步失败（超时/5xx/坏 JSON）时 usage summary 仍 200，且沿用旧价
- [ ] 常见 Claude/Codex model 字符串能命中价表（单测样例）
- [ ] `go test` 覆盖 store 定价与（若有）sync 包；相关文档补一句同步来源
- [ ] 不破坏现有 usage report/summary/breakdown 契约字段

## Notes

- 复杂度：中等；需 `design.md` + `implement.md` 后再 `task.py start`。
- 本任务主要改 **server/store**；monitor 无强制改动。
