# API 契约与 Mock

## Goal

冻结监控端、服务端、Android 共用的状态枚举与 HTTP/WS 契约，并提供可联调的 mock 服务。

## Parent

- 父任务：`07-18-multi-device-agent-status`
- 顺序：本任务最先；**无前置子任务**

## Requirements

- 定义会话状态枚举：`confirm` | `working` | `done` | `idle`
- 定义上报/查询/历史 REST 与 WebSocket 消息类型（与父任务 `design.md` 对齐并可微调）
- 用 Go 实现最小 mock server（内存态即可）：鉴权、report、查询、WS 广播
- 输出 OpenAPI 或等价 JSON schema / 示例 payload，路径约定在仓库内固定位置

## Acceptance Criteria

- [x] 仓库内有契约文档（路径明确，如 `docs/api.md` 或 `api/openapi.yaml`）
- [x] mock 可用预共享密钥鉴权
- [x] `POST report` 后 `GET machines/sessions` 能读到对应会话
- [x] WebSocket 在 report 后能收到变更或 notification 类消息
- [x] 示例 curl / 说明可让后续子任务直接对接

## Out of Scope

- 真实 SQLite 持久化、生产级部署
- Codex/Claude 真实采集
- Android UI

## Dependencies

- 无代码依赖；产品与设计见父任务 `prd.md` / `design.md`
