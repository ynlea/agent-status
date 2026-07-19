# 实施计划：多端 Agent 状态监控系统

> 本任务当前目标是 **规划完成**；真正写代码前需用户评审并 `task.py start`。  
> 因交付面大，建议 start 后拆成子任务分别实现。

## 阶段总览

| 阶段 | 内容 | 可独立验收 |
|------|------|------------|
| P0 契约 | OpenAPI/JSON schema、共享状态枚举、假数据联调 | 契约文档 + mock server |
| P1 Server | 鉴权、report、查询、WS、短历史清理 | curl/wscat 测通 |
| P2 Monitor | Codex 扫描 + Claude hook + 上报 | 本机双 Agent 会话可见 |
| P3 Android | 配置、列表、实时、通知开关 | 真机查看 + 红灯通知 |
| P4 打磨 | 安装文档、节流、离线/重连、可选 FCM | 双机日常可用 |

## 子任务（已创建，均 planning）

1. `07-18-api-contract` — 契约与 mock（先做）
2. `07-18-server-core` — 服务端核心
3. `07-18-monitor-agent` — Linux/Windows 监控端
4. `07-18-android-app` — Android 客户端
5. `07-18-docs-deploy` — 部署与使用说明

依赖：1 → 2；2 与 3/4 联调；5 在 2–4 基本可用后。  
实现时对**当前子任务**执行 `task.py start`，不要 start 父任务当实现目标。

## 有序清单（实现时）

### P0

- [x] 冻结 `state` 枚举与 report/query/ws 消息类型  
- [x] 写最小 mock server（内存态）  
- [x] 确认技术栈：Go（Server/Monitor）+ Kotlin（Android）

### P1 Server

- [x] 配置：监听地址、共享密钥、TTL、历史条数  
- [x] `POST /report` 合并 sessions、更新 machine 心跳  
- [x] `GET` 机器/会话/历史  
- [x] WebSocket 广播变更与 notification  
- [x] 定时清理过期 done/idle 与历史  
- [x] 基础日志（无敏感字段）

### P2 Monitor

- [x] 配置文件：server、key、machine_name  
- [x] Codex scanner：rollout 文件 → 会话状态  
- [x] Claude hook 子命令 + 示例 hooks 片段  
- [x] 上报循环：变更立即报 + 心跳  
- [x] Linux 构建；Windows 交叉编译验证  

### P3 Android

- [x] 首次配置页（URL + 密钥）  
- [x] 机器/会话列表 UI（状态色）  
- [x] WebSocket 实时刷新  
- [x] 通知渠道与红/黄/绿开关（默认仅红）  
- [x] 断线重连与错误提示  

### P4

- [x] README：私有部署、反代/隧道、hooks 配置  
- [x] 通知合并/最小间隔  
- [x] （可选）FCM  
- [x] 端到端：Linux + Windows 同时在线  

## 验证命令（占位，实现后替换）

```bash
# Server
curl -sH "Authorization: Bearer $KEY" $URL/api/v1/machines

# Monitor dry-run
./agent-status-monitor --print-sessions

# Hook smoke
echo '{"hook_event_name":"PermissionRequest","session_id":"t","cwd":"/tmp"}' | ./agent-status-monitor claude-hook
```

## 风险与回滚

| 风险 | 缓解 |
|------|------|
| Codex 确认态不准 | 先上 working/done，confirm 迭代校准 |
| 无 FCM 漏通知 | 文档加白名单；后续加 FCM |
| 双端工作量大 | 严格子任务；先 Linux monitor + Server + App |

## Start 前检查

- [x] 产品决策写入 `prd.md`  
- [x] 调研 `research/status-sources.md`、`research/android-push.md`  
- [x] `design.md` 架构与契约  
- [x] 用户确认技术栈：Go + Kotlin  
- [x] 用户评审通过后 `task.py start`（并拆子任务）  
