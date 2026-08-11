# Codex subagent 不作为独立会话

## Goal

Codex 主会话 spawn 的 subagent 不出现在主会话列表里；点进主会话详情后可以看到子会话列表与各自状态。

## Confirmed facts

- Codex 每个 subagent 单独写 `rollout-*.jsonl`；`session_meta` 含 `thread_source=subagent`、`id`（子 thread）、`session_id`/`parent_thread_id`/`forked_from_id`（主 thread）、`agent_nickname` / `agent_path`。
- 当前 monitor 用文件名 stem 当 `SessionID`，不识别父子，导致 subagent 与主会话并列。
- 会话列表是扁平 `Session`；`SessionDetailPage` 只展示单条会话字段，无子会话区。
- 服务端 `sessions` 表无 parent 字段；`ApplyReport` 按机器全量快照 upsert/删除。
- 灵动岛 / 首页统计会遍历全部 `sessions`，若不区分 subagent 会重复计数。

## Product decisions

| 决策 | 结论 |
|------|------|
| 主列表 | 只显示主会话（无 parent 的 root） |
| 详情 | 可看该主会话下的子会话（昵称/路径、状态、摘要） |
| 主会话状态 | 折叠：主+子取优先级最高状态（confirm > working > done > idle），避免主文件未更新时列表看起来空闲 |
| 子会话上报 | 仍上报为独立行，但带 `parent_session_id`；列表侧过滤 |
| 用量 | 本任务不改 token 归并 |
| Claude | 不改 |

## Requirements

1. monitor 识别 Codex subagent（`thread_source=subagent`，兼容 parent/forked 字段与 `source.subagent`）。
2. 建立子→主关联：用主会话 `session_meta.id` 与子会话 `parent_thread_id` 对齐，写出主会话对外 `session_id`（保持主文件既有 ID 规则）。
3. 上报字段扩展：
   - `parent_session_id`（空=主会话）
   - 可选展示用：`agent_nickname`（或复用 display_name 放昵称）
4. Scan 与 file-watch 行为一致。
5. 服务端存储并回传 `parent_session_id`；全量快照逻辑兼容新字段。
6. 移动端/桌面：
   - 主列表、灵动岛会话聚合：只计 root
   - 会话详情：展示子会话列表（状态 + 名称 + 简短 message）
7. 单元测试覆盖：仅主、主+多子、纯 orphan 子（无主文件时不进主列表）。

## Acceptance Criteria

- [ ] 主会话 + N 个 subagent 时，主列表只出现 1 条 Codex 主会话。
- [ ] 子 agent 在工作时，主会话列表状态至少为 working/confirm（折叠生效）。
- [ ] 进入该主会话详情可见全部子会话及其状态；子会话不单独出现在主列表。
- [ ] 无 subagent 的普通 Codex 会话行为与现网一致。
- [ ] `go test ./internal/monitor/ ./internal/store/ ./pkg/apitypes/ -count=1`（及相关已有测试）通过。
- [ ] 移动端模型/详情能解析并展示子会话（至少手工或现有结构可验证）。

## Out of scope

- 子会话再进二级详情页、操作子会话。
- token 用量归并到主会话。
- 以 `state_5.sqlite` 替代 rollout 扫描。
- Claude subagent 展示改造。

## Notes

- 复杂任务：需 `design.md` + `implement.md`，评审后再 `task.py start`。
