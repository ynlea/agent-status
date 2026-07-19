# 部署与使用文档

## Goal

写清个人私有部署、监控端安装、Claude hooks、外出访问与通知注意点。

## Parent

- 父任务：`07-18-multi-device-agent-status`
- **依赖**：`server-core`、`monitor-agent`、`android-app` 基本可用后再写终稿（可先草稿）

## Requirements

- 服务端启动/配置（密钥、端口、可选 compose）
- 监控端 Linux/Windows 安装与开机启动建议
- Claude Code hooks 配置示例（指向 monitor 的 hook 子命令）
- 外出访问：VPN / 反代 / 隧道注意 TLS 与密钥
- Android 安装与通知省电白名单说明
- 隐私：上报字段边界

## Acceptance Criteria

- [x] 按文档可从零完成：起服务 → 上监控端 → 打开 App 看到状态
- [x] hooks 示例可复制修改路径后使用
- [x] 明确默认通知策略与开关位置
- [x] 不引导使用第三方通知 App 作为主路径

## Out of Scope

- 营销网站、多语言完整本地化

## Dependencies

- 实现侧：`07-18-server-core`、`07-18-monitor-agent`、`07-18-android-app`
