# Implement: 远程管理 cc-switch 供应商

单任务交付。建议顺序：**契约与类型 → server 存储/API → monitor 适配与轮询 → App UI → 联调与回归**。

## Checklist

### A. 契约与共享类型

- [ ] `pkg/apitypes` 增加 providers / commands 请求响应结构体
- [ ] 更新 `docs/api.md` 与 `api/openapi.yaml`（与实现同步）
- [ ] 约定 status 枚举与错误码（offline 由 App 结合 machine.online 判断）

### B. Server

- [ ] SQLite migration：`provider_snapshots`、`machine_commands`
- [ ] `ApplyProvidersReport`、命令 `Enqueue` / `Pull` / `Complete` / 超时扫描
- [ ] 路由：
  - `POST /api/v1/providers/report`
  - `POST /api/v1/commands/pull`
  - `POST /api/v1/commands/{id}/result`
  - `GET /api/v1/machines/{id}/providers`
  - `POST /api/v1/machines/{id}/commands`
  - `GET /api/v1/commands/{id}`
- [ ] 结果处理时剥离 payload 中的 api_key
- [ ] 单元测试：入队串行、pull lease、超时、快照替换、鉴权 401
- [ ] 可选：WS `providers_updated` / `command_updated`（可二期，MVP 用 REST 轮询）

### C. Monitor

- [ ] `internal/monitor`：`ccswitch` 包（读库、patch、switch CLI）
- [ ] codex：TOML 字符串行级替换 `model` / `base_url`；auth key
- [ ] claude：JSON 深合并 env + 顶层 model；禁止抹掉 hooks
- [ ] 列表映射脱敏 DTO
- [ ] `command_poll_sec` 循环：pull → 执行 → result（成功附带最新 snapshot）
- [ ] 周期/命令后 `providers/report`
- [ ] 配置项：`cc_switch_db`、`cc_switch_bin`、`command_poll_sec`
- [ ] 测试：用临时 sqlite fixture 测 read/patch；CLI 可用 fake bin
- [ ] Windows/Linux 路径（home 下 `.cc-switch`）

### D. Mobile

- [ ] `RestClient`：providers list、create command、get command
- [ ] 设备详情入口 + Codex/Claude Tab
- [ ] 列表 / 当前标识 / 切换确认
- [ ] 编辑表单（按 app 字段）；api_key 空=不改
- [ ] 命令状态轮询与错误展示
- [ ] 文案：运行中会话不保证立即跟随
- [ ] 无快照/离线空态

### E. 验证

- [ ] `go test ./...`（server + monitor）
- [ ] 手工：本机 monitor 连 mock/server，App 切换 codex 与编辑 claude 字段
- [ ] 确认 `cc-switch provider current -a codex|claude` 与 live 文件变化
- [ ] 确认日志无 key
- [ ] 回归：会话 report、usage、机器改名

## Validation commands

```bash
go test ./pkg/apitypes/... ./internal/server/... ./internal/monitor/...
go build -o /tmp/agent-status-server ./cmd/server
go build -o /tmp/agent-status-monitor ./cmd/monitor
# mobile
cd mobile && flutter test && flutter analyze
```

联调（示例）：

```bash
# 起 server 后
# monitor 配置 server_url + key，观察 providers/report 与 commands/pull
curl -sS -H "Authorization: Bearer $KEY" "$BASE/api/v1/machines/$MID/providers"
curl -sS -X POST -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  "$BASE/api/v1/machines/$MID/commands" \
  -d '{"app":"codex","type":"switch_provider","payload":{"provider_id":"…"}}'
```

## Risk files

| 区域 | 风险 |
|------|------|
| `internal/monitor` 写 `settings_config` | 损坏 hooks / TOML → 仅 patch 约定键 + 测试 fixture |
| 命令队列并发 | 双 monitor 同 machine_id → lease + 单 running |
| 密钥进 SQLite 命令表 | 完成后剥离；日志字段白名单 |
| App 只读假设的 spec | 控制面仅供应商；不扩展会话审批 |

## Rollback points

1. Server migration 可保留空表；App 隐藏入口即对用户关闭功能。
2. Monitor 设 `command_poll_sec=0` 禁用执行。
3. 错误 patch：用户本机 `~/.cc-switch/backups` 人工恢复（文档一句即可）。

## Definition of done

- PRD 验收项全部勾选。
- design 中 API 与实现一致（docs 已更新）。
- 测试通过；手工切换/编辑链路跑通至少 codex 与 claude 各一次。
- 未实现新建/删除、其它 app、长连接下行。
