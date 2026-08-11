# Implement（待 start 后执行）

1. `pkg/apitypes`：Session 增 `LastAssistantMessage`、`Cwd`  
2. store sqlite/memory：两列 migrate + 读写 + 单测  
3. monitor：  
   - Claude/Codex 上报完整 `cwd`，`display_name` 仍用 basename  
   - Claude `lastAssistantFromTranscript`  
   - Codex 解析 assistant 正文  
   - 全文采集单测（不截断）  
4. App：Session 模型、详情页 UI（头+路径全文+正文）、首页/设备页 onTap  
5. `go test ./internal/monitor/ ./internal/store/`  
6. 发版：server → monitor → mobile  

当前阶段：**设计已写入 design.md，待你确认后 `task.py start` 再实施。**
