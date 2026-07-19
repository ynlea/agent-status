# Android 客户端

## Goal

Kotlin Android App：配置私有服务、只读查看多机会话、本 App 系统通知（可配置）。

## Parent

- 父任务：`07-18-multi-device-agent-status`
- **依赖**：`07-18-api-contract`；联调优选 `07-18-server-core`

## Requirements

- 首次配置：服务 URL + 预共享密钥
- 按机器分组展示会话列表；多会话同时可见；状态色区分
- WebSocket（或轮询降级）实时刷新
- 系统通知由本 App 发出；红/黄/绿开关可配；默认仅红开
- 只读：无远程确认/输入

## Acceptance Criteria

- [x] 错误密钥有提示且看不到数据
- [x] 服务端存在多会话时列表同时显示
- [x] 会话状态变化后 UI 在合理时间内更新
- [x] 开启红灯通知时，confirm 变化可弹出本 App 系统通知
- [x] 关闭某色开关后该色不再通知

## Out of Scope

- iOS
- FCM 必选（可后加）
- 远程控制 Agent

## Dependencies

- 契约：`07-18-api-contract`
- 联调：`07-18-server-core`
