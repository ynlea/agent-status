# Implement: 多端 Token 用量监控

## Order（建议按子任务）

父任务：`07-19-multi-device-token-usage` 只做跨端口径与最终验收。  
子任务各自 `task.py start`，互不并行改同一文件冲突时串行。

### Child A — 契约 + 服务端

**依赖**：无  

1. 扩展 `pkg/apitypes`：UsageEvent、UsageReportRequest、Summary、Breakdown  
2. 更新 `docs/api.md` + `api/openapi.yaml`  
3. `internal/store`：migrate `usage_events`、`model_prices`；ApplyUsageReport；QuerySummary/Breakdown  
4. 内置公开价表 seed（Claude / GPT-Codex 常见模型）  
5. `internal/server`：路由 `POST /usage/report`、`GET /usage/summary`、`GET /usage/breakdown`  
6. 单测：幂等入库、Claude/Codex 字段聚合、命中率边界、未知模型估价  

**验证**

```bash
go test ./pkg/apitypes ./internal/store ./internal/server
# 起 server 后 curl summary / breakdown
```

### Child B — 监控端解析与上报

**依赖**：Child A 的 API 可用（或先用 mock 契约）  

1. `internal/monitor`：Claude usage 解析器 + 单测样例 JSONL  
2. Codex token_count 解析（复用/扩展现有 rollout 读取，注意 billed = input-cached）  
3. cursor + 全量回填状态机 + 分批 POST `/api/v1/usage/report`  
4. 文件变更监听 + 10min 兜底；`usage_enabled` 配置  
5. 与现有 session report 并行，互不阻断  

**验证**

```bash
go test ./internal/monitor
go run ./cmd/monitor -config monitor.json
# 观察服务端 usage_events 增长；重跑无重复计数
```

### Child C — Flutter 用量页

**依赖**：Child A 查询 API  

1. `RestClient` 增加 usage API  
2. domain models + repository  
3. 路由 `/usage` + MainShell Tab  
4. UI：时间快捷、设备/渠道筛选、Hero、breakdown 列表、reasoning 展开、费用免责声明  
5. 空态 / 错误态 / 下拉刷新  

**验证**

```bash
cd mobile && flutter test
flutter run   # 真机或模拟器走完整筛选
```

### Parent 集成验收

1. 两台 machine_id 数据隔离 + 全部合计  
2. 今天 / 1d / 7d / 30d / 自定义 与本机脚本对拍（允许小误差说明）  
3. 会话状态监控不回归：`go test ./...` + 手动 WS 通知  
4. 确认无正文入库  

## Validation commands（总）

```bash
export PATH="$HOME/.local/go/bin:$PATH"
go test ./...
go build -o bin/agent-status-server ./cmd/server
go build -o bin/agent-status-monitor ./cmd/monitor
cd mobile && flutter analyze && flutter test
```

## Risk / rollback

| 风险 | 缓解 |
|------|------|
| 全量回填 IO 大 | 后台、限速批次、可中断续传 |
| 重复计数 | dedupe_key 主键 + 单测 |
| Codex cache 双计 | 上报前减 cached；契约写清 |
| 价表过时 | 标注估算；后续热更新 |
| 与 session report 耦合 | 独立 endpoint |

回滚：`usage_enabled=false`；服务端停路由；手机隐藏 Tab。

## Before task.py start

- [x] prd.md 决策齐全  
- [x] design.md 完成  
- [x] implement.md 完成  
- [x] 子任务已建：`07-19-token-usage-server` → `monitor` → `mobile`  
- [ ] 用户审阅规划  
- [ ] 通过后 start **Child A（server）**，不要 start 父任务做实现  
