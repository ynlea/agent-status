# Token 用量：契约与服务端

## Goal

落地用量 API 与 SQLite 存储，使 curl 可按时间/设备/渠道/模型查询汇总与 breakdown，并支持幂等批量入库与估算费用。

## Parent

`07-19-multi-device-token-usage` — 口径与设计以父任务 `prd.md` / `design.md` 为准。

## Dependencies

无。本子任务最先实现。

## Requirements

- 新增 `UsageEvent` 等契约与 `docs/api.md` / openapi
- `POST /api/v1/usage/report` 幂等批量写入
- `GET /api/v1/usage/summary` 与 `breakdown`（group_by agent|model|machine|day）
- 表 `usage_events`、`model_prices`；内置公开价表 seed
- 聚合：真实用量、新增输入、输出、reasoning、cache、命中率、估算费用
- 不影响现有 session report / history

## Acceptance Criteria

- [x] `go test ./pkg/apitypes ./internal/store ./internal/server` 通过
- [x] curl 上报样例事件后 summary/breakdown 正确
- [x] 重复 dedupe_key 不双计
- [x] 未知模型不导致接口 500

## Status

实现完成（2026-07-19）：`/api/v1/usage/*` + SQLite/Memory + 价表 + 文档。
