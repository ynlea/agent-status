# 服务端核心

## Goal

实现个人私有部署的 Go 服务端：鉴权、多机会话汇总、短历史、实时推送。

## Parent

- 父任务：`07-18-multi-device-agent-status`
- **依赖**：`07-18-api-contract` 契约冻结后开始（可复用 mock 演进为真服务）

## Requirements

- Go 实现；配置监听地址、预共享密钥、历史 TTL/条数
- `POST /api/v1/report` 合并机器心跳与会话
- `GET` 机器列表、会话列表、短历史
- WebSocket 推送 session/machine/notification 事件
- SQLite（或等价）持久化短历史；定时清理
- 日志不含对话全文等敏感字段

## Acceptance Criteria

- [x] 错误密钥无法访问受保护接口
- [x] 两台逻辑机器同时 report 后列表均可查询
- [x] 单机多会话同时存在且状态可更新
- [x] 状态变化可经 WS 收到 notification（字段完整）
- [x] 过期/超量历史会被清理（可用缩短 TTL 测）
- [x] 本地单二进制或 `go run` 可启动

## Out of Scope

- FCM 真实下发（可预留接口）
- 监控端采集、Android UI
- 多用户账号体系

## Dependencies

- 契约：`07-18-api-contract`
