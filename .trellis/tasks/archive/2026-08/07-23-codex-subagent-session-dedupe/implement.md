# Implement: Codex subagent 会话层级

## Checklist

1. **契约**  
   - [ ] `pkg/apitypes/types.go`：`Session` 增加 `ParentSessionID`  
   - [ ] 相关 JSON fixture / http 测试如有硬编码结构则顺带兼容

2. **monitor 解析**  
   - [ ] `codexRolloutState` 增加 thread 元数据字段（threadID、parentThreadID、isSubagent、nickname、agentPath）  
   - [ ] `applyLine` 处理 `session_meta`  
   - [ ] `session()` 产出时带上临时 thread 信息（或并行结构）  
   - [ ] 抽出 `attachCodexParents` + `foldCodexRootStates`  
   - [ ] `ScanCodex` 与 `CodexFileSource.Snapshot` 走同一后处理

3. **store**  
   - [ ] sqlite migrate 增加 `parent_session_id`  
   - [ ] ApplyReport / ListSessions 读写该字段  
   - [ ] memory store 同步

4. **测试**  
   - [ ] fixture：主 + 2 subagent（其一 working）→ Scan 结果 root 数=1，parent 折叠为 working，children 带 parent  
   - [ ] 无 meta 的旧 rollout 仍当 root  
   - [ ] watcher snapshot 同样断言（可轻量）

5. **mobile**  
   - [ ] `models.dart` 字段  
   - [ ] `home_page` / `status_repository` 列表与 demo 过滤 root  
   - [ ] `island_controller` / `island_models` 聚合只计 root  
   - [ ] `session_detail_page` 子会话区块

6. **验证命令**  
   ```bash
   go test ./internal/monitor/ ./internal/store/ ./pkg/... -count=1
   # mobile 有改动时：
   cd mobile && dart analyze lib
   ```

## Risky points

- SessionID 仍用文件名 stem：父子关联必须靠 meta UUID 映射，不能假设 ID 相等。  
- Watcher 增量更新单文件后需 **全量 re-fold**（或维护 parent 索引），不能只更新单文件 state。  
- 灵动岛漏过滤会导致 working 数虚高。

## Rollback

- 回退 monitor 后处理与客户端过滤即可；DB 列可留。

## Ready for start when

- 用户确认本 PRD/design/implement  
- 无未决产品问题
