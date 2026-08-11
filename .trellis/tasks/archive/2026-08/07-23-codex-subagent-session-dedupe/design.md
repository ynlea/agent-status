# Design: Codex subagent 会话层级

## Boundaries

| 层 | 职责 |
|----|------|
| monitor `codex.go` / `codex_watcher.go` | 解析 session_meta、标记 parent、折叠 root 状态 |
| `apitypes.Session` | 契约：`parent_session_id`（及可选 nickname 字段） |
| store / report | 持久化与列表回传新字段；快照删除逻辑不变 |
| mobile 列表 / 灵动岛 | root 过滤 |
| `SessionDetailPage` | 同 machine+agent 下 `parent_session_id == 当前 session_id` 的子列表 |

## Contracts

### Session 扩展（向后兼容）

```text
parent_session_id string  `json:"parent_session_id,omitempty"`  // 空=root
// display_name：子会话优先 agent_nickname，否则 agent_path base，否则原逻辑
```

旧客户端忽略未知字段；旧 monitor 不上报 parent 时行为与现网一致（全部当 root）。

### 关联规则

1. 解析每个 rollout 的 `session_meta`（可多条，取最新有效）：
   - `thread_id` = `id`
   - `logical_session_id` = `session_id`（Codex 语义上主会话 UUID）
   - `is_subagent` = `thread_source=="subagent"` 或存在 `parent_thread_id`/`forked_from_id` 或 `source.subagent`
2. 对每个 **非 subagent** 文件，建立 `thread_id → reported SessionID` 映射。  
   `reported SessionID` 继续用当前文件名 stem 规则，避免历史会话 ID 断裂。
3. subagent 的 `parent_session_id` = 映射[`parent_thread_id`]；映射缺失时用 `parent_thread_id` 字符串兜底（仍非 root，主列表不可见）。
4. **Root 状态折叠**（仅改 root 的 `state`/`updated_at`/`message` 可选）：
   - 收集该 root 的自身状态 + 所有 `parent_session_id==root.SessionID` 的子状态
   - `state` = 优先级最高者
   - `updated_at` = 成员中最新
   - `message`：保持 root 自身摘要；若 root 空且子有摘要，可用「子任务: {nickname}」一类短文案（不暴露长 prompt）

子会话自身 `state` 不折叠，详情里看真实子状态。

### 数据流

```text
rollout files
  → per-file codexRolloutState (+ thread meta)
  → []Session (raw, with parent_session_id)
  → foldRoots([]Session)
  → Report / Snapshot
  → store sessions (+ parent_session_id column)
  → API / WS
  → client: list roots; detail filter children
```

Scan 与 Watcher 共用同一套「parse → attach parent → fold」函数，避免双路径漂移。

## Store

- `ALTER TABLE sessions ADD COLUMN parent_session_id TEXT NOT NULL DEFAULT ''`
- INSERT/SELECT/UPSERT 带上该列
- `ListSessions` 仍返回全部（含子）；过滤放客户端，避免详情缺数据。若日后要服务端分页再拆接口。

## Client

- `Session.fromJson` 读 `parent_session_id`
- 列表数据源：`sessions.where((s) => s.parentSessionId.isEmpty)`
- 灵动岛 working 计数、聚合：只对 root
- 详情：在现有卡片下增加「子会话」区块；空则不展示

## Compatibility

- 已入库的「假独立」子会话：新 monitor 上报后带 parent，全量快照会更新；旧 ID 若仍是子文件 stem，会变成带 parent 的行，主列表消失。
- 不强制清理历史 history 行。

## Trade-offs

| 方案 | 取舍 |
|------|------|
| 子会话仍为独立 store 行 + parent 字段 | 详情简单、WS upsert 自然；列表要处处 filter |
| 只嵌套在 parent.children JSON | 列表干净，但 store/WS 改动大、局部更新难 |
| 选用前者 | 与现有扁平模型一致 |

## Rollback

- 回退 monitor：不再写 parent，全部当 root（回到问题态）
- 列可保留；空 parent 无害
