# PRD：会话详情展示 Agent 最后消息

## 背景

App 点击会话目前只跳设备页，没有会话详情。用户希望点开会话时能看到 **Agent 最后一段输出**，用来快速判断任务进展。

本机验证结论：

- **Codex**：rollout jsonl 里 `response_item` + `role=assistant` 的 `content` 含完整文本，可提取。
- **Claude**：`~/.claude/projects/<proj>/<sessionId>.jsonl` 里 `type=assistant` + `message.role=assistant` 的 text 块可提取。
- **现状监测端**：两边都**没有**上报 Agent 最后消息；Claude 只采用户 prompt 摘要，Codex 对 `agent_message` 只记事件名。

## 目标

1. 监测端采集 Claude / Codex 会话的 **Agent 最后消息**（可截断）。
2. 随现有 session 上报到服务端（扩展字段，兼容旧客户端）。
3. App 点击会话进入详情，展示该内容，形成「任务大致情况」可读视图。

## 非目标（本版不做）

- 不上报完整对话历史 / 工具调用正文全文。
- 不做实时流式输出同步。
- 不改动用量统计链路。

## 产品约定

- **主展示**：Agent 最后消息（**完整原文，不截断**）。
- **辅展示**：用户意图摘要（现有 `message` 作标题）、状态、Agent、设备、更新时间；**项目路径为完整绝对路径**（`cwd`）。
- **长度**：最后消息按完整文本上报与渲染；列表卡片仍只用短摘要 `message`，避免撑爆列表。
- **隐私**：仅最后一条 assistant 可见文本；不采集密钥文件、工具 stdout 大段（Codex 工具输出仍不采）。
- **详情页**：独立会话详情路由；头部含状态/Agent/标题/设备/完整路径；正文为完整最后消息（可滚动）。

## 验收标准

- [ ] Codex 会话在 Agent 有回复后，上报字段含最后 assistant **完整**文本。
- [ ] Claude 会话在 transcript 有 assistant 后，上报字段含最后 assistant **完整**文本。
- [ ] 无 assistant 时字段为空，不影响状态机与现有 `message` 摘要逻辑。
- [ ] 服务端存储/列表/推送能带回该字段；旧监测端不上报时 App 不崩溃。
- [ ] App：点击会话进入详情页，能看到最后消息；从首页与设备页会话列表均可进入。
- [ ] 相关 monitor 单测覆盖解析；App 基础解析用例（如有）。

## 备注 / 开放点

- 字段命名倾向：`last_assistant_message`（与现有 `message` 用户摘要并存），避免覆盖标题语义。
- 截断长度、是否可配置，实现阶段在 design 里定默认值。
- 任务目录：`.trellis/tasks/07-20-session-last-agent-message`（planning，未 start）。
