# 执行计划:添加 pi 监控与用量统计

## 实施清单(按序)

### Step 1:用量解析(backend/monitor)
- [ ] `internal/monitor/usage_parse.go` 新增 `ParsePiUsageFile(path string, fromOffset int64) (events []apitypes.UsageEvent, newOffset int64, err error)` 与 `CollectPiUsageFiles(sessionsDir string) ([]string, error)`(仿 `ParseClaudeUsageFile` / `CollectClaudeUsageFiles`)。
  - 逐行 `type=message`(assistant + toolResult 带 usage)+ `type=compaction`(顶层 usage)。
  - DedupeKey=`"pi:" + base(path) + ":" + entry.id`;SessionID=header id;model 沿用逻辑见 design。
  - 全零 usage 跳过;`message.timestamp` 仅作备用,优先 entry `timestamp`。

### Step 2:UsageSyncer 接线
- [ ] `internal/monitor/usage_sync.go`:
  - `discoverFiles()` 追加 pi 收集;
  - `usageKindOrInfer` 白名单加 `"pi"`;
  - `SyncOnce()` switch 加 `case "pi"`。
- [ ] `internal/monitor/config.go`:新增 `PiSessionsDir` 字段 + LoadConfig 默认 `~/.pi/agent/sessions`。

### Step 3:会话监控
- [ ] 新文件 `internal/monitor/pi.go`:`ScanPi(root string) ([]apitypes.Session, error)`(design §5 字段映射;状态阈值:5min working / 24h 过滤;标题:session_info.name → user 摘要 → 文件名 stem)。
- [ ] `cmd/monitor/main.go` `collect()` 追加 `ScanPi`,Source 兜底 `"pi-file"`。

### Step 4:server 白名单
- [ ] `internal/store/usage.go` `sanitizeUsageEvent`:白名单加 `"pi"`。

### Step 5:单测
- [ ] `internal/monitor/usage_parse_test.go` 增补 `ParsePiUsageFile` 用例:assistant usage、toolResult 嵌套 usage、compaction usage、全零跳过、DedupeKey 稳定性、fromOffset 增量。
- [ ] `internal/monitor/pi_test.go`(新):`ScanPi` 用例:标题优先级、状态阈值、24h 过滤、cwd、LastAssistantMessage。
- [ ] `internal/store/usage_test.go`(若有):`sanitizeUsageEvent` 接受 `agent=pi`。

### Step 6:mobile 端
- [ ] 绘制 `mobile/assets/images/agent/agent_pi.png` + `agent_pi_glyph.png`(参考 codex 图标风格;若无设计资源,先用简单 "π" 字形占位图)。
- [ ] `mobile/lib/ui/widgets/assets.dart`:`agent()` / `agentGlyph()` 加 `case 'pi'`。
- [ ] 搜索 mobile lib 下其他 agent 显示名映射(`usage_page.dart` / `session_card.dart` / `providers_page.dart` / `models.dart`),有则补充 pi。

## 验证命令

```bash
# 后端
cd /home/ynlea/projects/agent-status
go build ./...
go vet ./...
go test ./internal/monitor/ ./internal/store/ -run 'Pi|Usage|Scan' -v

# 端到端(本机有真实 pi 会话)
go run ./cmd/monitor --once --config <本地 monitor.json> 2>&1 | grep -i pi
# 然后查 server DB:sqlite3 agent-status.db "select agent,count(*) from usage_events where agent='pi';"

# mobile
cd mobile && flutter analyze
```

## 风险点 / 回滚点

- **高风险文件**:`internal/monitor/usage_sync.go`(SyncOnce 热路径,改动只加分支不动既有逻辑,风险低)、`cmd/monitor/main.go` collect()。
- **格式漂移**:pi 会话格式若后续版本变化(DedupeKey 依赖 entry id),需回归单测。当前 v3 已验证。
- 每步完成即跑对应单测;全部改动增量、可独立回滚。

## 上线前检查

- [ ] `go test ./...` 全绿
- [ ] `flutter analyze` 无新增告警
- [ ] 本机 monitor --once 后 DB 出现 agent=pi 用量记录
- [ ] App 会话/用量页可见 pi 图标与数据
