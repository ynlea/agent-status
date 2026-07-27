# 安装脚本：重建用量 + Windows 无窗自启

## Goal

1. 在 Linux / Windows 安装管理脚本中提供 **重建用量** 能力：有服务端则清服务端用量事件，有监测端则清本机用量游标并重启监测端触发全盘重扫；操作需 **二次确认**。
2. 修复 Windows 开机自启会弹出前台控制台窗口、关窗即杀进程的问题，改为后台无窗常驻。

## Confirmed facts

- 管理入口：`scripts/install.sh`（Linux systemd --user）、`scripts/install.ps1`（Windows 任务计划 + pid 文件）。
- 服务端 SQLite 默认：`{INSTALL_ROOT}/data/agent-status.db`（`AGENT_STATUS_DB`）。
- 用量表：`usage_events`（`dedupe_key` 主键）；冲突时 **不覆盖 token 字段**，仅可能补 unknown 模型。故只清监测端游标无法修正服务端虚高。
- 监测端游标默认：`~/.agent-status/usage-cursors.json`（`monitor.json` 的 `usage_state_file` 可覆盖）。
- 当前 Windows `Enable-Role` 直接 `Register-ScheduledTask` 执行 console 子系统的 `.exe`，登录时会弹黑窗；`Start-Role` 虽用 `-WindowStyle Hidden`，与自启路径不一致。
- 既有菜单无「重建用量」项；`update` 只换二进制。

## Product decisions

| 决策 | 结论 |
|------|------|
| 命令名 | `rebuild-usage`（交互菜单单独一项） |
| 二次确认 | 交互：两次明确确认（第二次需输入 `YES`）；非交互仅 `-Yes` 不够，还要 `--confirm-rebuild-usage` / `-ConfirmRebuildUsage` |
| 清服务端 | 本机已装 server 且 DB 存在 → `DELETE FROM usage_events`（**不动** `model_prices`） |
| 清监测端 | 本机已装 monitor → 删除用量游标文件；解析 `monitor.json` 的 `usage_state_file`，缺省用默认路径 |
| 重扫 | 清游标后 **restart monitor**（有装才重启） |
| 角色检测 | 按本机是否存在对应二进制自动决定清哪一侧；可 `--role` / `-Role` 收窄 |
| Windows 自启 | 计划任务改为无窗启动，日志进 `logs/`，不绑前台终端 |
| 与 update 关系 | **独立命令**；文档可写「用量算法升级后建议跑 rebuild-usage」 |

## Requirements

1. **rebuild-usage**（sh + ps1 对称）
   - 探测 server / monitor 是否在本机安装。
   - 展示将执行的动作清单。
   - 二次确认后执行。
   - 清服务端：对 DB 执行 `DELETE FROM usage_events`（依赖 `sqlite3` CLI，缺失则明确报错）。
   - 清监测端游标 + restart monitor。
   - 交互菜单增加入口；`docs/install.md` 补用法。

2. **Windows 无窗自启**
   - `Enable-Role` 注册的任务启动后不出现前台控制台窗。
   - 关终端不应误杀（进程不依赖该终端）。
   - `Start-Role` 与自启路径行为一致。
   - 重新 `enable` 可覆盖旧任务定义。

## Acceptance Criteria

- [x] `install.sh rebuild-usage` / `install.ps1 rebuild-usage` 可用，二次确认后按本机角色清理。
- [x] 仅 monitor：只清游标并重启 monitor；仅 server：只清 `usage_events`。
- [x] 两端都有：两边都清，然后重启 monitor。
- [x] 非交互误触有防护（不能只靠一次 `-Yes` 就删库）。
- [x] Windows 登录自启不再弹前台黑窗；进程后台跑、日志写入 `logs/`。
- [x] `docs/install.md` 有说明。

## Out of scope

- 手机端触发远程清库。
- 服务端 HTTP 管理 API 清用量。
- 修改用量解析算法（`07-27-codex-usage-total-delta`）。
- 改 Go 为 `windowsgui` 子系统（优先脚本层隐藏）。

## Notes

关联：`07-27-codex-usage-total-delta` 落地后，历史虚高需本命令校正。
