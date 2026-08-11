# 技术设计:添加 pi 监控与用量统计

## 架构与边界

监控端(monitor)是唯一需要新增逻辑的地方,沿用两条现有链路,pi 作为第三种 agent 接入:

```
pi 会话 jsonl ─┬─ ParsePiUsageFile ──> UsageSyncer ──> /api/v1/usage/report(agent=pi)
               └─ ScanPi ────────────> collect() ───> /api/v1/monitor/report(Source=pi-file)
```

server 端只改一处白名单;pricing/UI 聚合逻辑零改动(按 agent/model 通用)。

## 数据流与契约

### 1. 用量解析:ParsePiUsageFile(新,internal/monitor/usage_parse.go)

签名(仿 ParseClaudeUsageFile,无 delta 状态):

```go
func ParsePiUsageFile(path string, fromOffset int64) (events []apitypes.UsageEvent, newOffset int64, err error)
```

逐行处理 `type` 字段:

| entry type | 处理 |
|---|---|
| `message` + `message.role == "assistant"` | 取 `message.usage`,生成事件 |
| `message` + `message.role == "toolResult"` 且带 `usage` | 计入(pi 自身 totals 含 tools 上报用量) |
| `compaction` 且带顶层 `usage` | 计入(摘要生成消耗) |
| 其他(session/model_change/custom/...) | 跳过 |

字段映射(UsageEvent):

| 字段 | 来源 |
|---|---|
| Agent | `"pi"` |
| Model | `message.model`;toolResult/compaction 无 model → 沿用最近 assistant 的 model(cursor 内可用 `startModel`,文件内取"最后一个已知 model");仍空 → `"unknown"` |
| SessionID | header `id`(uuid);缺失 → 文件名去掉 `.jsonl` |
| InputTokens / OutputTokens | `usage.input` / `usage.output` |
| CacheWriteTokens / CacheHitTokens | `usage.cacheWrite` / `usage.cacheRead` |
| ReasoningTokens | 0(pi 无单独 reasoning 字段) |
| OccurredAt | entry 级 `timestamp`(ISO,parseTimeField 已支持) |
| DedupeKey | `"pi:" + filepath.Base(path) + ":" + <entry id>`(entry id 为 8-hex,跨文件需带文件名防撞) |

跳过条件:usage 全零(与 claude 一致);`fromOffset` 截断/超限时从 0 重读(复用 SyncOnce 现有逻辑)。

### 2. 文件收集:CollectPiUsageFiles(新,同文件)

```go
func CollectPiUsageFiles(sessionsDir string) ([]string, error)
```

递归 Walk 收集所有 `*.jsonl`(目录形如 `--<path>--/`,递归即可)。sessionsDir 为空返回空。

### 3. UsageSyncer 接线(internal/monitor/usage_sync.go)

- `discoverFiles()`:追加 `CollectPiUsageFiles(u.Cfg.PiSessionsDir)`,`add(p, "pi")`。
- `usageKindOrInfer()`:白名单加 `"pi"`。
- `SyncOnce()` switch:新增 `case "pi": events, newOff, err = ParsePiUsageFile(path, cur.Offset)`。
- fileCursor 复用现有 `LastModel` 字段作为 pi 的 `startModel`(mid-file 读取首行是 toolResult 时沿用),无新增字段。

### 4. 配置(internal/monitor/config.go)

```go
PiSessionsDir string `json:"pi_sessions_dir,omitempty"` // 默认 ~/.pi/agent/sessions
```

### 5. 会话监控:ScanPi(新文件 internal/monitor/pi.go)

```go
func ScanPi(root string) ([]apitypes.Session, error)
```

逐文件扫描,每文件推导一个 Session:

| Session 字段 | 来源 |
|---|---|
| Agent | `"pi"` |
| SessionID | header `id`(uuid) |
| DisplayName | `session_info.name` 优先;否则第一条 user 消息摘要(`ShortSummary`,复用现有工具);仍空 → 文件名 stem |
| State | 最后消息 timestamp(或 fileMod)距今 ≤5min → `working`;否则 `idle`;idle 且 >24h → 该会话不上报(与 codex 过滤一致) |
| Message | 第一条 user 消息摘要(working 时) |
| Cwd | header `cwd` |
| LastAssistantMessage | 最后一条 assistant 消息文本(thinking 块除外,取 text 块) |
| Source | `"pi-file"`(main.go collect 里兜底赋值,同 codex 模式) |
| UpdatedAt | 最后消息 timestamp |

性能:大文件(600KB+)用 `bufio` 流式读,只保留必要状态(第一条 user、最后 assistant、最后时间),不做全量内存驻留。达到 codex `loadCodexRollout` 的"只留 meta + 尾部窗口"同等效果——pi 简单起见全量流式扫(每行即弃)。

### 6. monitor main 接线(cmd/monitor/main.go collect())

`collect()` 中追加 `monitor.ScanPi(cfg.PiSessionsDir)`,Source 空则补 `"pi-file"`,与 codex/claude 合并。

### 7. server 端(internal/store/usage.go)

`sanitizeUsageEvent` 白名单:`e.Agent != "pi" && e.Agent != "claude" && e.Agent != "codex"` → 丢弃。
(会话上报 `sqlite.go` 仅校验 Agent 非空 + State.Valid,无需改动。)

### 8. mobile 端

- 新增图标:`mobile/assets/images/agent/agent_pi.png` + `agent_pi_glyph.png`(参考现有 codex 图标风格绘制)。
- `mobile/lib/ui/widgets/assets.dart`:`agent()` / `agentGlyph()` 加 `case 'pi'`。
- 检查 usage_page / session_card / providers_page 是否有按 agent 显示名的映射需要补充(若有 `agentDisplayName` 之类函数一并加)。

## 兼容性与迁移

- 向后兼容:新增 agent 不影响现有 claude/codex 链路;monitor.json 无 `pi_sessions_dir` 时用默认路径。
- 存量数据:pi 历史会话通过首轮全量扫描自然回填(UsageSyncer BackfillDone 机制)。
- server DB:无需迁移(usage 表按 agent 字符串存储)。

## 权衡

- **纯文件扫描 vs extension 钩子**:扫描方案零安装、零侵入,复用现有轮询(默认 60s);代价是实时性上限为轮询周期,且需解析文件(600KB 级文件每 tick 仅当 size 变化才解析,成本可控)。
- **toolResult 嵌套 usage 计入**:与 pi 自身 `/session` totals 口径一致;代价是 model 需沿用(个别极端文件可能归错模型,影响可忽略)。
- **不做会话树分支处理**:pi 单文件多分支按时间序取最后活动,简单且足够(分支在文件内是低频操作)。

## 回滚

- 全部改动为增量(新增函数/文件 + 白名单放宽),不触及现有数据路径;回滚 = 还原 8 处文件改动。
- `pi_sessions_dir` 配置错误时仅影响 pi 采集,claude/codex 不受影响。
