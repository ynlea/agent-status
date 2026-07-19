# Implement: 模型价表 OpenRouter 同步

## Checklist

### 1. 价表存储与查价改造

- [x] 在 `Store`（sqlite + memory）实现：`UpsertModelPrice`、价表缓存、`LookupModelPrice` 读缓存
- [x] `seedModelPrices`：bundled `DO NOTHING`；新增 override 强制 upsert
- [x] 修正 `bundledPublicPrices` 中明显过期项（作兜底即可）
- [x] `EstimateCostUSD` / 聚合路径改为经 store Lookup
- [x] 单测：写入后查到；override 优先级

### 2. 归一化

- [x] 增强 `NormalizeModelID`：`.` → `-`；覆盖 openrouter 风格 id
- [x] 单测：Claude 日期后缀、provider 前缀、gpt 点号

### 3. OpenRouter 同步包

- [x] 新增 `internal/pricing`：Fetch + Map + Sync
- [x] 价换算 `per_token * 1e6`；cache 默认 0
- [x] upsert 规则不覆盖 `override`
- [x] 假 HTTP 服务器单测 Fetch + Sync

### 4. Server 接入

- [x] 读配置/环境变量
- [x] 启动：seed → override → 可选异步 sync + ticker
- [x] 失败不阻断 HTTP Serve
- [ ] （可选）鉴权后的手动 sync 端点 — 未做，启动+定时足够

### 5. 文档与回归

- [x] `docs/deploy.md` / `docs/api.md` 补充价表同步说明
- [x] `go test ./internal/store/ ./internal/pricing/ ./internal/server/` 通过
- [ ] 手测：有网环境可观察 sync 日志（部署时验证）

## Validation commands

```bash
go test ./internal/store/ ./internal/server/ ./pkg/apitypes/
# 若新建 pricing 包：
go test ./internal/pricing/
```

可选手测：

```bash
curl -sH "Authorization: Bearer $KEY" \
  "$BASE/api/v1/usage/summary?from=...&to=..."
```

## Review gates

- [ ] override 不会被 openrouter 冲掉
- [ ] 查询路径不读「仅内存常量」
- [ ] 无密钥泄漏到日志
- [ ] 与父任务费用口径一致（分项 × token / 1e6）

## Rollback

- 关 `PRICING_SYNC_ENABLED`，仅用 bundled + override seed
- 或回退 commit；开发环境可重建 `model_prices`

## Order notes

1. 先 DB Lookup 改造（即使暂不同步，行为已正确）
2. 再 sync 包与启动钩子
3. 最后文档与过期 seed 校正
