# 多端 Agent 状态监控系统

## Goal

个人私有部署下，把多台机器上 Codex / Claude Code 的会话状态汇总到中心服务，用 Android App 实时查看并接收可配置通知，从而知道何时需要回到本机处理。

## Confirmed Facts

- 参考产品：`kongkongyo/agent-status-light`（Windows 本机悬浮灯，红/黄/绿 + 通知）
- 状态语义可复用：红=需确认，黄=工作中，绿=刚完成，空闲=无活跃任务
- 状态来源方向：Codex 本地会话、Claude Code hooks、必要时退回进程/前台活动
- 当前仓库几乎为空（仅 Trellis 脚手架），属从零产品规划
- 用户要求：先调研与规划，再进入详细实现

## Product Decisions

| 决策 | 选择 | 说明 |
|------|------|------|
| 使用对象 / 部署 | 个人使用，私有部署 | 不做多用户公网 SaaS；不做完整账号体系 |
| 首版平台 / Agent | Linux + Windows；Claude Code + Codex | 暂不扩展其他 Agent |
| 状态粒度 | 多会话实时可见 | 单机可并发多会话，手机同时看到各会话状态 |
| 手机交互 | 只读 + 通知 | 不远程确认/操作；处理回本机 |
| 手机端形态 | 先 Android | 首版不做 iOS；Web/PWA 非主形态 |
| 本机 UI | 无悬浮灯 | 监控端仅后台上报 |
| 通知入口 | 自有 Android App | 系统通知由本 App 展示 |
| 通知范围 | 红/黄/绿均可配置 | 默认仅红灯开启，黄/绿默认关闭 |
| 接入鉴权 | 服务地址 + 预共享密钥 | 不做扫码配对 |
| 历史保留 | 短历史 | 当前活跃 + 约 24h 或最近约 50 条 |
| 上报内容 | 状态 + 标识 + 短展示名 | 无对话全文 / 完整 prompt |
| 访问范围 | 支持外出远程访问 | VPN / 反代 / 隧道均可 |
| 技术栈 | Go + Kotlin | Server/Monitor 用 Go；Android 用 Kotlin |

## Requirements

1. **服务端**：私有部署；校验预共享密钥；接收多监控端上报；维护机器与会话状态；向已接入的 Android 客户端触达通知事件；提供查询当前状态与短历史。
2. **监控端（Linux / Windows）**：后台运行；采集 Claude Code 与 Codex 多会话状态；按约定字段上报；无本机悬浮灯。
3. **Android 客户端**：配置服务地址与密钥；按机器分组展示多会话实时状态；只读；以本 App 系统通知展示状态变化；红/黄/绿通知开关可配（默认仅红开）。
4. **隐私边界**：不上报对话全文与完整 prompt；字段限于状态、会话 ID、Agent 类型、短展示名等。
5. **部署形态**：支持局域网与外出访问（访问通道由部署解决，产品不绑死单一方案）。

## Acceptance Criteria

### 规划阶段（本任务当前）

- [ ] `prd.md` 记录目标、决策、范围、可测试验收方向
- [ ] 完成关键调研并写入 `research/`
- [ ] `design.md` 给出架构边界、数据流、契约与取舍
- [ ] `implement.md` 给出分阶段落地清单与验证方式
- [ ] 用户评审通过后再 `task.py start`

### 首版产品验收方向（实现阶段细化）

- [ ] 至少 2 台监控端（可为 Linux + Windows）能同时在线上报
- [ ] 单机多个 Claude/Codex 会话状态可在 App 中同时看到并更新
- [ ] 红灯等状态变化可在用户开启对应开关时由本 App 弹出系统通知
- [ ] 错误密钥无法接入；无密钥无法读到状态
- [ ] 短历史可查；过期/超量记录会被清理
- [ ] 不出现对话全文类敏感字段上报

## Out of Scope（首版）

- 多用户 SaaS、完整账号、计费
- iOS 客户端
- 本机悬浮状态灯
- 远程批准权限 / 远程输入
- 以 Bark / Telegram / ntfy 等第三方 App 作为主通知入口
- 其他 Agent（Cursor、Aider 等）
- 长期归档与审计分析
- 未调研前锁定具体技术栈

## Open Questions

1. ~~产品范围是否还需追加首版能力？~~ → 无
2. ~~状态源？~~ → 见 `research/status-sources.md`（Codex: rollout jsonl；Claude: hooks）
3. ~~Android 通知？~~ → 见 `research/android-push.md`（自有 App 弹通知；实时流 + 可选 FCM）
4. ~~技术栈？~~ → Server/Monitor = Go，Android = Kotlin
5. 规划是否评审通过，可否拆子任务并 `task.py start`？（待你确认）

## Child Tasks

| 子任务 | 说明 | 依赖 |
|--------|------|------|
| `07-18-api-contract` | API 契约与 Mock | 无 |
| `07-18-server-core` | Go 服务端核心 | api-contract |
| `07-18-monitor-agent` | Go 监控端 | api-contract（联调 server） |
| `07-18-android-app` | Kotlin Android | api-contract（联调 server） |
| `07-18-docs-deploy` | 部署与使用文档 | server + monitor + android 基本可用 |

父任务保持规划/集成视角；**实现从子任务逐个 start**。

## Notes

- 父任务 status=`planning`，不直接作为实现目标。
- 规划产物：`prd.md`、`design.md`、`implement.md`、`research/*`。


## Completion

- [x] 子任务全部交付（api/server/monitor/android 源码/docs）
- [x] Android 需在装有 SDK 的环境编译安装
