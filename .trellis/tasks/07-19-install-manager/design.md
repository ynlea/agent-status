# Design: install-manager

## Architecture

```
curl|bash / irm|iex
        │
        ▼
 scripts/install.sh  ·  scripts/install.ps1     (UX + 编排)
        │
        ├─ GitHub Release 下载二进制
        ├─ 写配置 / 备份
        ├─ 注册常驻（systemd user / 计划任务）
        ├─ 探测 Agent + 调 monitor --init --claude
        └─ status/start/stop/restart/config
                │
                ▼
 ~/.local/share/agent-status/   or  %LOCALAPPDATA%\agent-status\
   bin/agent-status-server
   bin/agent-status-monitor
   config/server.env | monitor.json
   data/agent-status.db          (server)
   logs/
   state/                        (pid 等，Windows)
```

**边界**

- 安装器：下载、布局、服务生命周期、配置读写、Agent 探测与触发 init。
- 不实现业务：上报/hooks 合并仍在 `cmd/server`、`cmd/monitor`。
- 不走 Docker。

## CLI 契约（两平台语义对齐）

```text
install.sh <command> [options]
install.ps1 <command> [options]

commands:
  (default / install)  安装或升级
  status               查看角色状态
  start | stop | restart
  enable | disable     开机自启（能力内）
  config get|set       配置
  init-agents          探测并初始化
  uninstall            停服务、可选删文件（默认保留配置）

common options:
  --role server|monitor|all
  --yes / -y           非交互
  --version TAG        指定 Release 版本，默认 latest
  --server-url URL     monitor
  --key KEY            server/monitor 共享密钥
  --addr ADDR          server 监听，默认 :8080
  --no-init-agents     跳过 hooks 初始化
  --no-enable          不安自启
```

无 TTY 且未 `--yes`：失败退出（避免挂起）。

## Release 资产

建议命名（CI 生成）：

| 资产 | 说明 |
|------|------|
| `agent-status-server-linux-amd64` | |
| `agent-status-server-linux-arm64` | |
| `agent-status-monitor-linux-amd64` | |
| `agent-status-monitor-linux-arm64` | |
| `agent-status-server-windows-amd64.exe` | |
| `agent-status-monitor-windows-amd64.exe` | |
| `install.sh` / `install.ps1` | 可选随 Release 附带；主入口仍可用 raw main |

校验：发布脚本计算 `sha256sums.txt`；安装器下载后校验（若 sums 存在）。

## 常驻模型

### Linux（systemd --user）

- 单元名：`agent-status-server.service`、`agent-status-monitor.service`
- 写入：`~/.config/systemd/user/`
- `ExecStart` 指向安装目录二进制 + 配置
- server 环境文件：`config/server.env`（`AGENT_STATUS_KEY`、`AGENT_STATUS_ADDR`、`AGENT_STATUS_DB`）
- monitor：`-config .../config/monitor.json`
- `enable` 需要用户会话 linger 时提示 `loginctl enable-linger`（可选文档，不强制脚本改系统）

### Windows

- 启动：`Start-Process` 隐藏窗口或写 helper；pid 记入 `state/*.pid`
- stop：按 pid / 进程名温和结束
- 自启：当前用户「登录时」计划任务 `AgentStatusServer` / `AgentStatusMonitor`
- 不做 SCM 服务

## 配置

| 角色 | 文件 | 来源 |
|------|------|------|
| server | `config/server.env` | 安装时生成 key（若未传）、addr、db 路径 |
| monitor | `config/monitor.json` | 基于 `configs/monitor.example.json` 字段 |

- `config set`：只改给定键，保留其余。
- 升级：覆盖二进制，配置存在则不覆盖（除非 `--force-config`）。

## Agent 探测与初始化

| Agent | 探测 | 动作 |
|-------|------|------|
| Claude Code | `claude` 在 PATH，或 `~/.claude` / `%USERPROFILE%\.claude` 存在 | `bin/agent-status-monitor --init --claude --config <monitor.json>` |
| Codex | `codex` 在 PATH，或 `~/.codex` 存在 | 确保 monitor.json 中 app-server/file-watch 合理；不改 Codex 自身配置 |

探测结果写入交互摘要；非交互默认：发现 Claude 则 init，可用 `--no-init-agents` 关闭。

## 兼容与迁移

- 已有手动 `monitor.json` / 二进制：安装器支持 `--config-from PATH` 导入（实现阶段可选；至少文档说明拷贝到安装目录）。
- 与现有 `docs/deploy.md` 命令并存；文档增加「推荐安装器」章节，保留手动路径。

## Trade-offs

| 选择 | 利 | 弊 |
|------|----|----|
| shell/ps1 而非 Go ctl | 贴 curl 体验、无额外二进制 | 双脚本维护、Windows 逻辑偏脆 |
| 用户级 systemd | 免 root | 无图形会话时需 linger |
| 公开仓 + raw 脚本 | 真一键 | 仓库需 Public；脚本变更即全网生效 |
| 无 Docker | 简单 | 已有 compose 用户需看文档 |

## Rollback

- 升级前备份：`bin/*.bak`、`config/*.bak-<ts>`
- `uninstall --keep-config`（默认）/ `--purge`
- 失败的下载不替换正在用的二进制（先下到 tmp 再 atomic move）

## Security

- HTTPS only（GitHub）
- 不在日志打印完整 key（status 可显示已配置/掩码）
- hooks 只合并 agent-status 自己的 command 条目（已有 monitor 逻辑）
