# 交互式安装与本机管理（服务端/监测端）

## Goal

为 agent-status 提供「一键入口」的本机安装与日常管理能力：用户可选择部署服务端或监测端；监测端能探测本机 Agent 并完成必要初始化（如 Claude Code hooks）；同时支持状态查看、配置更新、启停与开机自启；兼容交互式与非交互式两种用法。

## Confirmed Facts（仓库已证实）

- 组件：`cmd/server`、`cmd/monitor`、Docker/`docker-compose.yml`（**安装器不使用 Docker**）、文档 `docs/deploy.md`。
- 监测端已支持 Claude hooks 初始化：`agent-status-monitor --init --claude --config <path>`（幂等合并 hooks，拒绝 `go run` 临时路径）。
- Codex 监测依赖本机 Codex 会话/app-server，无单独 hook 初始化命令；配置见 `configs/monitor.example.json`。
- 文档已建议 Linux 用 systemd user service，Windows 用计划任务或 NSSM。
- 远程仓库：`https://github.com/ynlea/agent-status`（按**公开仓**交付；当前仍为 Private，发布前需改为 Public；尚无 Release 流水线）。

## Requirements

### R1 安装入口

- Linux：`curl -fsSL https://raw.githubusercontent.com/ynlea/agent-status/main/scripts/install.sh | bash`
- Windows：下载或 `irm .../install.ps1 | iex`（等价入口）
- 默认**交互式**菜单；支持**非交互**参数/子命令（CI 与脚本）。
- 角色可分别安装：**服务端** / **监测端**（同一台机器可两者都装）。

### R2 服务端安装与管理

- 从 GitHub Release 下载对应平台预编译 `agent-status-server`，写入配置（key、addr）与数据目录。
- 常驻方式：
  - Linux：systemd **user** unit
  - Windows：后台进程 + 可选「登录时」计划任务（不做完整 Windows Service）
- 管理：`status` / `start` / `stop` / `restart` / 配置查看与更新 / 开机自启开关（平台能力内）。
- **不提供 Docker 安装路径**（项目保持轻量；compose 仅留文档给高级用户）。

### R3 监测端安装与管理

- 下载 `agent-status-monitor`，生成 `monitor.json`（server_url、key、machine 标识等）。
- 探测本机 Agent（至少 Claude Code / Codex）。
- 初始化：
  - Claude：调用已安装二进制的 `--init --claude`
  - Codex：写入合理监测开关（app-server / file-watch），不改写 Codex 全局配置
- 管理动作与 R2 对齐（按角色区分 unit/任务名）。

### R4 交互与非交互

- 交互：选角色 → 填 server_url/key（或生成 key）→ 是否 init hooks → 是否开机自启。
- 非交互示例（语义对齐两平台）：
  - `install.sh install --role monitor --server-url URL --key KEY --yes`
  - `install.sh install --role server --addr :8080 --key KEY --yes`
  - `install.sh status|start|stop|restart --role <server|monitor>`
  - `install.sh config set --role monitor --server-url URL`
  - `install.sh init-agents --claude`（可选）
- 缺必填参数：非零退出，不留下半安装状态。

### R5 安全与可维护

- 仓库内不出现真实密钥；示例配置用占位符。
- 升级保留配置；改写前备份。
- 固定安装根目录与日志路径。
- Claude hooks 必须指向已安装的固定路径二进制。

## Acceptance Criteria

- [ ] Linux / Windows 均可交互安装服务端或监测端，安装后 `status` 可读。
- [ ] 非交互监测端安装在给定 server_url/key 后可完成，进程可启动。
- [ ] 监测端能探测 Claude/Codex；有 Claude 时 hooks 初始化成功且二次幂等。
- [ ] Linux：用户级 systemd 可 start/stop/restart/enable；Windows：脚本可启停，可选登录自启。
- [ ] 配置更新不丢失未改字段；升级保留 key 与路径。
- [ ] Release 提供 Linux amd64/arm64 与 Windows amd64 的 server/monitor 资产。
- [ ] 文档覆盖双平台用法、目录布局、卸载要点；明确不走 Docker 安装器。

## Out of Scope

- 手机 App / Flutter 安装。
- Docker/compose 纳入安装菜单。
- 公网 HTTPS/隧道自动开通。
- 多机编排与服务发现。
- Windows 完整 Service（SCM）包装。
- 改动状态协议或业务 API 语义。
- Go 版 manage CLI（本任务为 shell/ps1 全家桶）。

## Decisions

| 项 | 决定 |
|----|------|
| 二进制 | GitHub Release 预编译，不走安装器内 `go build` |
| 架构 | Linux amd64/arm64；Windows amd64 |
| 仓库 | 公开仓设计 curl 体验；发布前改 Public |
| 入口 | shell 全家桶：`scripts/install.sh` + `scripts/install.ps1` |
| 平台 | 双平台同步交付 |
| 服务端 Docker | **不做**（轻量，二进制 only） |
| 安装目录 | Linux：`~/.local/share/agent-status`（数据/二进制）、`~/.local/bin`（可选 shim）；Windows：`%LOCALAPPDATA%\agent-status` |
| 服务模型 | Linux systemd user；Windows 进程 + 计划任务自启 |

## Open Questions

无阻塞项。实现前仅需用户审阅 `design.md` / `implement.md`。

## Notes

- 复用 `cmd/monitor` Claude init，脚本不平行实现 hooks 合并。
- 现有 Docker 文件保留，但不接入安装器。
