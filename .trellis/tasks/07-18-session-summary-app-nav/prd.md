# 会话摘要与 App 导航重设计

## Goal

让手机端一眼认出「哪台机器、哪个目录、在做什么」：监控端上报短任务摘要，App 用清晰导航与更现代的界面展示活跃任务与设备会话。

## User value

- 通知/列表不再只有目录名和 `stopped` 这类状态词
- 历史会话变多时，首页仍只关注当前活跃任务
- 界面更接近现代控制台风格，而不是原型堆砌页

## Confirmed facts（仓库与约定）

- 契约字段：`display_name`、`message`、状态、机器/会话 id；隐私约定：**不写完整 prompt / 对话全文**（`docs/api.md`）
- Claude hook 已解析 `cwd`，`display_name = basename(cwd)`；`message` 目前是状态标签
- Claude `UserPromptSubmit` 已接入 hook 列表；尚不提取提示词摘要
- Codex 侧已有 cwd，但 `user_message` 也只记事件名，不写正文
- Android 为 Kotlin + Compose Material3 单页原型：配置/开关/机器列表挤在同一屏
- 已有 API：`GET /machines`、`GET /machines/{id}/sessions`、`GET /history`、WS `notification`

## Product decisions already agreed

1. **任务识别**：`display_name` 继续用会话目录；`message`（或等价短字段）放用户提示词的**短摘要**（约 40～60 字，首行/截断，去换行）
2. **导航**
   - 首页：仅非 idle（`confirm` / `working` / `done`），跨设备汇总，紧急度排序
   - 设备页：全部注册设备（在线状态）
   - 设备详情：该设备会话；活跃在上，空闲可折叠
   - 设置：服务地址、密钥、通知开关，不塞进列表
3. **完成态停留**：`done` 约 **10 分钟**后降为 idle（与现有监控一致）。这是「会话仍开着时，绿灯给人看一眼」的窗口，不是猜进程死活。
4. **会话真正结束**：Claude 已有 `SessionEnd` → 直接 idle；不靠扫描 `claude` 进程 PID（不可靠，且多会话难对齐）。Codex 继续用事件/文件活跃度与现有超时。
5. **技术栈**：继续原生 Compose；视觉参考 [new-api](https://github.com/QuantumNous/new-api) default Web 气质，Material3 转译
6. **主题**：跟随系统浅色/深色
7. **风格转译要点**：卡片分区、状态 chip/色条、底栏「首页 / 设备 / 设置」、主标题=摘要、副标题=目录 · agent · 机器

## Requirements

### R1 监控端 / 上报

- Claude：`UserPromptSubmit` 生成短摘要写入 session 的 `message`（或明确的摘要字段），后续 Stop/Done 等状态变更保留该摘要直到下一轮提示覆盖
- 摘要规则：去空白与换行、限长、禁止原文过长；失败时回退为目录名/状态标签
- 隐私：不上报完整 prompt，日志同样不落全文
- Codex：与 Claude 同一套摘要规则；从 user message 类事件提取正文并截断写入 `message`，不落全文

### R2 App 导航与信息架构

- 底部三入口：首页 / 设备 / 设置
- 首页只展示活跃任务；点条目可进对应设备详情
- 设备页列出全部机器；点机器进详情会话列表
- 设备详情：该机会话，活跃优先，idle 折叠

### R3 App 视觉

- 重做布局与组件层级，去掉「配置+列表一锅炖」
- 视觉对齐 new-api 现代控制台气质（卡片、chip、连接状态、主副标题层级）
- 通知文案：标题=状态语义；正文=`目录 — 摘要`（有摘要时）

### R4 契约兼容

- 优先复用现有 `message` 承载短摘要，避免无必要的破坏性字段变更
- 若确需新字段，须同步 `pkg/apitypes`、OpenAPI、Android 模型与 mock

## Acceptance Criteria

- [ ] Claude 新一轮用户提示后，session/`notification` 能带上短摘要，且不含完整长 prompt
- [ ] Codex 用户消息事件后同样写入短摘要，规则与 Claude 一致（限长、无私密全文）
- [ ] 完成态通知/列表能同时看出目录与任务摘要
- [ ] App 首页仅活跃任务；设备页可看全部设备；设备详情可看该机会话
- [ ] 设置独立入口；首次与后续改配置不阻塞主列表浏览（已配置后）
- [ ] 视觉上具备卡片/chip/主副标题层级，不再是单页 Checkbox 原型
- [ ] 主题跟随系统浅色/深色
- [ ] 现有隐私约定仍成立；测试覆盖摘要截断与 hook 状态机关键路径

## Out of scope（当前草案）

- 换成 Flutter / RN / 纯 Web 客户端
- 在手机端展示完整对话内容
- 远程批准/在手机上操作本机 Agent（仍只读监控）
- 复杂图表看板（new-api 的用量图不在本任务）
- **历史页**（`/history` 时间线）：本版不做；API 保留，后续再做

## Open questions

1. ~~历史页是否纳入本任务？~~ → **不做**
2. ~~Codex 是否同步做短摘要？~~ → **与 Claude 一起做**
3. ~~默认主题？~~ → **跟随系统**
4. ~~首页「近期 done」保留多久？~~ → **约 10 分钟**（对齐现有 done→idle；真结束靠 SessionEnd）
5. ~~是否拆 parent/child？~~ → **不拆，单任务串行**

## Notes

- 规划产物：`prd.md` + `design.md` + `implement.md`；用户审阅通过后再 `task.py start`
- UI 参考：new-api `web/default`（现代）为主
