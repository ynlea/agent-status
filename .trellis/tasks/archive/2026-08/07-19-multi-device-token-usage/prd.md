# 多端 Token 用量监控（采集器+服务端+手机）

## Goal

在现有 agent-status 三端架构上，让手机能按设备 / 渠道 / 模型 / 时间范围查看本地 Claude 与 Codex 的 token 用量明细与汇总，体验接近 cc-switch 的用量面板，但不绑定单机桌面。

## User value

- 多台电脑各自跑 Claude / Codex 时，手机可统一看「今天 / 近 1 天 / 7 天 / 30 天 / 自定义范围」用了多少。
- 能区分渠道与模型，看清真实用量、新增输入、输出、缓存命中与命中率。
- 只上报统计数据，不上传对话正文。

## Confirmed facts（仓库已有）

- 项目已是 **监控端 `cmd/monitor` + 服务端 `cmd/server`（Go/SQLite）+ Flutter `mobile/`**。
- 现有契约见 `docs/api.md`：`POST /api/v1/report` 上报会话状态；手机查 machines / sessions / history；共享 key 鉴权。
- 监控端已会扫 Codex `~/.codex/sessions` 与 Claude hook 状态，但 **API / store / mobile 均无 token 字段**。
- 多设备已有 `machine_id` / `machine_name` / `platform` 模型，可复用。
- 本地日志口径（本会话实测）：
  - Claude：`~/.claude/projects/**/*.jsonl` 的 `assistant.message.usage`；cache read **不在** input 内。
  - Codex：`~/.codex/sessions/**/rollout-*.jsonl` 的 `event_msg/token_count`；cached **已含在** input 内，计费前需减掉。

## Requirements

### R1 采集（监控端）

1. 从本机 Claude / Codex 会话日志解析 token，不依赖代理拦截作为主路径。
2. 至少支持渠道：`claude`、`codex`。
3. 解析字段至少：
   - `input_tokens`（Claude 原生 input；Codex 为 raw input）
   - `output_tokens`
   - `cache_creation_tokens` / `cache_write`（Claude；Codex 可恒为 0）
   - `cache_read_tokens` / `cache_hit`（Claude 的 cache_read；Codex 的 cached_input）
   - `reasoning_tokens`（Codex；Claude 可 0）
   - `model`
   - 事件/会话时间（UTC）
4. 按渠道适配去重与口径（Claude 按 message.id；Codex 按 token_count 增量）。
5. 周期性或增量扫描后，把 **聚合统计** 上报服务端（不上报 prompt/正文）。
6. 上报必须带 `machine_id`，与现有状态上报同一台设备身份。
7. **历史回填：全量**。首次启用用量采集时，扫描本机 Claude / Codex 已有全部会话日志并导入；之后仅增量。全量扫描可后台进行，不阻塞状态监控；需可断点续传 / 幂等，避免重复计数。

### R2 服务端

1. 持久化用量明细或足够细的时间桶，支持按时间范围聚合查询。
2. 查询维度：
   - 时间：自定义 `from`/`to`，以及快捷：当天、近 1 天、7 天、30 天
   - 设备：全部 / 指定 `machine_id`
   - 渠道：全部 / claude / codex
   - 模型：全部 / 指定 model
3. 返回指标至少：
   - **真实用量**（统一体积口径，见下）
   - **新增输入**（渠道归一后的 billed/fresh input）
   - **输出**（含 Codex reasoning 是否并入输出需在 design 固定）
   - **缓存命中**
   - **缓存命中率**
   - **缓存写入**、事件/请求次数
   - **估算费用**（分项单价 × 对应 token；非账单）
4. 鉴权沿用现有 Bearer key；隐私约束与现网一致。
5. **模型价格预留**：维护可扩展的模型价表（input / output / cache_read / cache_write，必要时 reasoning）；优先采用公开列表价；未知模型走 fallback 或显示「未定价」；MVP 可不做用户自定义改价 UI，但数据结构与 API 要能扩展。

### R3 手机端（Flutter 主客户端）

1. 新增用量页（或 Tab），风格可参考 cc-switch 汇总卡 + 筛选 + 分渠道/分模型。
2. 支持快捷时间范围与自定义范围。
3. 支持设备切换 / 全部设备合计。
4. 支持渠道筛选与模型细分列表。
5. 离线电脑时仍可查看 **已同步历史**；实时性以服务端最新入库为准。

### 统一指标口径（产品层）

| 展示名 | 计算 |
|--------|------|
| 新增输入 | Claude: `input`；Codex: `max(input - cached, 0)` |
| 输出 | Claude: `output`；Codex: 汇总默认 `output + reasoning`；明细可展开看 reasoning |
| 缓存命中 | Claude: `cache_read`；Codex: `cached` |
| 缓存写入 | Claude: `cache_creation`；Codex: `0` |
| 真实用量 | `新增输入 + 输出 + 缓存写入 + 缓存命中`（体积口径，非账单等价） |
| 缓存命中率 | `缓存命中 / (缓存命中 + 缓存写入 + 新增输入)`，分母为 0 时显示 `-` |

说明：真实用量用于跨渠道对比「处理量」。估算费用必须按分项单价计算，禁止用真实用量 × 单一单价。界面需标明「估算，非账单」。

## Acceptance Criteria

- [ ] 监控端能从本机 Claude / Codex 日志解析今日用量，并上报到服务端。
- [ ] 服务端可按 当天 / 1 天 / 7 天 / 30 天 / 自定义区间 返回汇总与分渠道、分模型明细。
- [ ] 手机端可选设备与时间范围，展示真实用量、新增输入、输出、缓存命中、缓存命中率与估算费用（标注非账单）。
- [ ] 价表覆盖 Claude / Codex 常见公开模型；未知模型不因缺价导致整页失败。
- [ ] Claude 与 Codex 口径不双重计 cache；单元测试覆盖两边样例日志。
- [ ] 上报与查询均不包含对话正文；仅统计字段。
- [ ] 两台及以上 `machine_id` 数据互不串扰，支持全部合计与单机筛选。
- [ ] 现有会话状态监控能力不回归（report sessions / WS 通知仍可用）。

## Out of scope（MVP）

- 代理拦截作为唯一数据源（可选后续增强）
- 与供应商发票自动对账
- MVP 用户自定义改价 UI（价表结构预留，改价可二期）
- Gemini / OpenCode 等其它渠道（可预留 agent 字段）
- iOS 单独适配优先级（Flutter 能跑即可）
- 服务端多用户账号体系（继续共享 key 即可）

## Parent / child 建议

| 子任务 | 可独立验收 |
|--------|------------|
| 契约 + 服务端存储与查询 API | curl 能按范围查出汇总 |
| 监控端 Claude/Codex 解析与上报 | 本机日志 → 服务端有数据 |
| Flutter 用量页 | 手机筛选并展示 |

父任务负责跨端验收与口径一致。

## Decisions

| 决策 | 结论 |
|------|------|
| 历史回填 | **C 全量**：首次启用扫全部本地 Claude/Codex 会话日志；之后增量；幂等、可后台 |
| 费用估算 | **要做估算 + 预留公开价表**；分项计价；未知模型 fallback；MVP 不做自定义改价 UI |
| Reasoning 展示 | **A**：汇总并入输出；明细可展开看 Codex reasoning |
| 同步节奏 | **A**：文件变更增量 + 5–15 分钟兜底扫描；全量回填仅首次/显式触发 |
| 价表更新 | MVP **内置公开价表**（随版本更新）；结构预留服务端覆盖，二期再做热更新 |

## Open questions

- 无阻塞项。细部实现见 `design.md` / `implement.md`。

## Notes

- 复杂任务：完成 `design.md` + `implement.md` 并经确认后，才 `task.py start`。
- 实现前不得把对话正文写入 DB 或 API。
