# Design: rebuild-usage + Windows hidden autostart

## Boundaries

| 组件 | 改动 |
|------|------|
| `scripts/install.sh` | 新命令、菜单、确认、清库/清游标、重启 |
| `scripts/install.ps1` | 同上 + 重写 `Enable-Role` 启动方式 |
| `docs/install.md` | 用法 |
| Go 服务端/监测端 | **不改**（除非后续发现无 sqlite3 必须加子命令；本版优先脚本 + sqlite3） |

## rebuild-usage 流程

```text
expand roles (default: 本机已装的 server/monitor)
  → 解析路径：
      server DB: server.env AGENT_STATUS_DB 或 data/agent-status.db
      monitor cursor: monitor.json usage_state_file 或 ~/.agent-status/usage-cursors.json
  → 打印计划
  → 确认 #1：「将删除用量数据，不可恢复」y/N
  → 确认 #2：输入 YES
  → stop monitor（若将清游标或即将 restart）
  → 若含 server 且 DB 存在：
      sqlite3 "$DB" "DELETE FROM usage_events;"
      （可选 VACUUM 不做，避免耗时）
  → 若含 monitor：
      rm -f 游标文件
  → start/restart monitor（若本机有 monitor）
  → 汇报结果
```

### 非交互

```bash
./install.sh rebuild-usage --role all --yes --confirm-rebuild-usage
```

```powershell
.\install.ps1 rebuild-usage -Role all -Yes -ConfirmRebuildUsage
```

仅 `-Yes` / `--yes` **不足以** 执行删除。

### 依赖

- `sqlite3` CLI：删除 `usage_events`。
- 缺失时：错误退出并提示安装（Linux `sqlite3` 包；Windows 可提示 winget/choco 或把 sqlite3 放 PATH）。不在本任务引入完整 DB 驱动。

### 安全

- 不删除 `model_prices`、sessions、machines。
- 不删整个 `agent-status.db` 文件。
- 二次确认文案标明影响范围。

## Windows 无窗自启

### 问题

计划任务 `Execute = agent-status-*.exe`（console 子系统）→ 登录弹黑窗 → 关窗 = 杀进程。

### 方案

`Enable-Role` 改为执行 **隐藏 PowerShell**，内部再 `Start-Process -WindowStyle Hidden` 并重定向日志、写 pid（与 `Start-Role` 共用逻辑，抽 `Start-RoleCore`）：

```text
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File <InstallRoot>\bin\start-role.ps1 -Role monitor
```

或 `-Command` 内联调用同一函数脚本。

推荐：安装时写入 `bin/start-hidden.ps1`（参数 Role），`Enable-Role` 与可选的 `Start-Role` 都走它，避免任务里塞超长 `-Command`。

任务设置：

- `AtLogOn` 当前用户
- `ExecutionTimeLimit` 关闭（0 / 不限）
- `MultipleInstances IgnoreNew`（若支持）
- `Hidden = $true`
- 不使用「只有在用户登录时运行」之外的 SYSTEM 账户（保持现用户环境变量与 Codex/Claude 路径）

### Start-Role

保持 Hidden + 日志；可改为调用 `start-hidden.ps1` 以单一路径。

## 菜单

Linux / Windows 交互菜单增加例如：

`9  重建用量   rebuild-usage`

（序号按现有 1–8 顺延。）

## 风险

| 风险 | 缓解 |
|------|------|
| 无 sqlite3 | 明确报错；文档写依赖 |
| 旧计划任务仍弹窗 | `enable` 时 `-Force` 覆盖；文档写需重新 enable |
| 误删 | 二次确认 + 专用 flag |
