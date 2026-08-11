# App 远程管理 cc-switch 供应商

## Goal

在轻芽 App 上对指定机器的本机 `cc-switch` 供应商做查看、切换与编辑，经服务端转发、由对应机器监控端执行，避免人必须坐在电脑前操作。

## Confirmed facts（仓库与本机已核实）

- 现网链路是单向上报：监控端 `POST /api/v1/report`（会话）与 `POST /api/v1/usage/report`（用量），App 主要只读；尚无「命令下行」通道。
- 鉴权统一为预共享 key（`Authorization: Bearer` / `X-Agent-Status-Key`）。
- 本机 `cc-switch` CLI（5.8.5）可非交互切换：`cc-switch use <id> -a <app>`；`provider list` 无 `--json`；`provider add/edit` 偏交互，不适合远程自动化。
- 本机真相源：`~/.cc-switch/cc-switch.db` 表 `providers`；密钥在 `settings_config`，列表上报必须脱敏。
- 会话上报默认 `report_interval_sec=60`；命令拉取需与会话上报解耦才能做到数秒级。
- 切换只改本机配置/当前项；**已在运行的会话不一定立刻跟随**（产品需明示）。

## Requirements

### 功能（MVP）

1. **覆盖 app**：`codex` 与 `claude`（同版交付）。
2. **列供应商 + 当前项**：监控端采集并上报脱敏快照；App 按机器 + app 查看。
3. **切换供应商**：App → 服务端命令 → 监控端 `cc-switch use <id> -a <app>` → 回报并刷新快照。
4. **编辑已有供应商**（不做新建/删除）：
   - 共用：`name`、`base_url`、`api_key`（未改则不传明文）。
   - codex：`model`（config TOML）。
   - claude：顶层 `model` 别名、`env.ANTHROPIC_MODEL`、`ANTHROPIC_DEFAULT_{HAIKU,SONNET,OPUS}_MODEL`、`ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN`。
   - 只 patch 约定键；Claude 不得整表覆盖以免冲 hooks。
   - 若改当前项，写完后再 apply live（再 switch 自身）。
5. **命令结果可见**：queued / running / succeeded / failed / timed_out；失败原因摘要；无明文 key 入日志。
6. **时延**：监控端轻量拉命令（约 5s），与会话 60s 上报解耦；在线机器数秒～十数秒内开始执行。

### 约束

- 命令绑定 `machine_id`，不得串机。
- 密钥不完整落盘到服务端/监控日志；App 展示掩码。
- 适配层读/写 `cc-switch.db` + CLI switch；不依赖交互 CLI、不默认依赖公网 `cc-switch-web`。
- 旧监控端忽略新路由/字段仍可跑会话与用量。
- **单任务交付**（不拆 server/monitor/mobile 子任务）。

## Acceptance Criteria

- [ ] App 能对在线机器看到 codex/claude 供应商列表与当前项（无明文 key）。
- [ ] App 切换后，目标机 `cc-switch provider current -a <app>` 与服务端快照一致（约定窗口内）。
- [ ] App 能编辑约定字段；Claude 含别名、ANTHROPIC_MODEL、三档 DEFAULT 映射。
- [ ] 在线机器上，下发后通常数秒～十数秒内开始执行；离线不假成功。
- [ ] 未知 id / 无 cc-switch / 写库失败时有明确失败态。
- [ ] 原有会话上报、用量、机器列表/改名不受影响。
- [ ] UI 或文案说明：切换/编辑不保证已在跑会话立即跟随。

## Out of scope

- 新建 / 删除供应商
- 整段 TOML 高级编辑、failover、测速/quota 远程化
- 跨机复制、WebDAV
- 多租户鉴权
- 运行中会话热切换保证
- gemini / opencode / hermes 等其它 app

## Open questions

（无阻塞项）

## Decisions log

| 决策 | 结论 |
|------|------|
| 增删 | MVP 不做 |
| app 范围 | codex + claude |
| Claude model 面 | 别名 + ANTHROPIC_MODEL + 三档 DEFAULT，对齐 cc-switch |
| 时延 | 秒级拉取，轻量拉命令与会话上报解耦 |
| 任务结构 | 不拆子任务 |
| App 入口 | 设备详情 → `/devices/:machineId/providers` |

## Implementation status

- 代码已实现并通过 `go test` / build / 相关 flutter analyze。
- 验收检查：PRD 主项 Pass；check 子代理修了 pull limit、超时清理、快照 machine 绑定、离线提示。
- 待真机：monitor 升级后连现网 server，App 实机切换/编辑一轮。

