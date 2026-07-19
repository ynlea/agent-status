# 部署与使用

从零到手机可见状态的最短路径。

## 1. 服务端

需要 Go 1.22+（或 Docker）。

```bash
export PATH="$HOME/.local/go/bin:$PATH"   # 若 Go 装在用户目录
export AGENT_STATUS_KEY='请换成足够长的随机串'

go run ./cmd/server -addr :8080 -key "$AGENT_STATUS_KEY" -db ./agent-status.db
```

或：

```bash
export AGENT_STATUS_KEY='请换成足够长的随机串'
docker compose up -d --build
```

健康检查：`curl -s http://127.0.0.1:8080/healthz` → `ok`  
契约说明：`docs/api.md`

### 常用参数

| 参数 / 环境变量 | 含义 | 默认 |
|-----------------|------|------|
| `-key` / `AGENT_STATUS_KEY` | 预共享密钥（必填） | 空 |
| `-addr` / `AGENT_STATUS_ADDR` | 监听地址 | `:8080` |
| `-db` / `AGENT_STATUS_DB` | SQLite 路径 | `agent-status.db` |
| `-history-ttl-sec` | 历史保留秒数 | 86400 |
| `-history-max` | 历史最大条数 | 50 |
| `-offline-after-sec` | 无心跳判离线 | 120 |

## 2. 监控端（本机）

```bash
cp configs/monitor.example.json monitor.json
# 编辑 server_url / key / machine_name
go build -o agent-status-monitor ./cmd/monitor
./agent-status-monitor -config monitor.json
```

一次性探测：

```bash
./agent-status-monitor -config monitor.json -print-sessions
./agent-status-monitor -config monitor.json -once
```

Windows 交叉编译：

```bash
GOOS=windows GOARCH=amd64 go build -o agent-status-monitor.exe ./cmd/monitor
```

### 开机启动建议

- Linux：systemd user service，`ExecStart=/path/agent-status-monitor -config /path/monitor.json`
- Windows：任务计划程序「登录时」运行，或 NSSM 注册服务

### Claude Code hooks

监控端可自动合并 Hooks（生命周期钩子）配置，不会删除既有的 Claude 设置；首次修改会在同目录保留 `settings.json.agent-status.bak`（设置备份）。先构建固定路径的二进制，再执行初始化：

```bash
go build -o bin/agent-status-monitor ./cmd/monitor
./bin/agent-status-monitor --init --claude --config ./monitor.json
```

初始化会写入：`SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PostToolUseFailure`、`PermissionRequest`、`Notification`、`Stop`、`StopFailure`、`SubagentStop`、`SessionEnd`。每条 agent-status 命令钩子带 `"async": true`，不阻塞 Claude 主会话。二次 init 会幂等更新命令路径并补上 `async`。不要使用 `go run` 执行初始化，因为它的临时二进制路径不能作为长期 Hook 命令。

子命令：`agent-status-monitor claude-hook --config monitor.json`（从 stdin 读 Hook JSON）。

状态：`PermissionRequest` / 部分 `Notification` → 红灯 `confirm`；工具与提交提示 → `working`；`Stop` / 正常 `SubagentStop` → `done`。Claude 无新 hook 时：`working` 45 分钟、`done` 10 分钟、`confirm` 30 分钟后降为 `idle`。

### Codex

两条通道（可并存）：

1. **app-server（优先）**：监控端启动 `codex app-server --stdio`，用 JSON-RPC 拉 `thread/list` / `thread/loaded/list`，并收 `thread/status/changed`、`turn/*` 等通知。状态变化会**立即触发上报**（不必等轮询周期）。进程退出会自动重启。  
2. **会话文件监听（普通 CLI 会话优先）**：监听 `~/.codex/sessions/**/rollout-*.jsonl` 的创建和写入；每个会话文件独立增量读取新增 JSONL 行，变化会立即上报。每分钟执行一次全量校准，处理遗漏事件、文件截断和监控端重启。
3. **全量文件扫描（兜底）**：文件监听不可用时，按原方式扫描会话文件并推断状态。

配置：

| 字段 | 含义 | 默认 |
|------|------|------|
| `codex_app_server` | 是否启用 app-server 通道 | `true` |
| `codex_file_watch` | 是否监听普通 Codex 会话文件 | `true` |
| `codex_sandbox_mode` | 传给 app-server 的 `sandbox_mode`（空=用 Codex 默认） | 空 |
| `report_interval_sec` | 心跳上报周期 | 15 |

AppArmor 等环境下若默认沙箱起不来，可在该机 `monitor.json` 设 `codex_sandbox_mode`（例如 `danger-full-access`），**不要在代码里写死**。stderr 会进监控日志，便于排查 bubblewrap 失败。

合并规则：同一会话若 app-server 给出 live 状态，优先生效；`notLoaded` 仍走文件监听或扫描。日志字段 `source`：`codex-app-server` / `codex-file-watch` / `codex-file` / `claude-hook`。

## 3. Android

见 `android/README.md`。用 Android Studio 打开 `android/` 编译安装。

1. 服务 URL：局域网可用 `http://电脑IP:8080`；外出需 VPN / 隧道 / 反代 HTTPS  
2. 密钥与服务端一致  
3. 允许通知；**默认仅红灯通知**；黄/绿在应用内开关  
4. 只读：手机上不能远程确认 Agent  

省电：把 App 加入厂商「无限制后台」/ 白名单，否则 WebSocket 可能被杀导致漏通知。首版无 FCM，依赖长连接与重连轮询。

## 4. 外出访问

任选其一，产品不绑死方案：

- Tailscale / Headscale：手机与服务器同虚拟网，URL 用 `http://100.x.x.x:8080`
- Cloudflare Tunnel / frp / 反代：对外 HTTPS，密钥仍必填
- 切勿在无 TLS 的公网明文裸奔密钥；至少用 VPN 或 HTTPS 反代

## 5. 隐私边界

上报/展示字段仅限：机器标识、agent 类型、session_id、短展示名、状态、可选短 message、时间。  
**不要**把对话全文或完整 prompt 写进 message 或日志。  
`message` 优先为用户提示词的短摘要（首行、约 48 字）；没有摘要时才用状态标签。

## 6. 通知策略

| 颜色 | 状态 | 默认 |
|------|------|------|
| 红 | confirm | 开 |
| 黄 | working | 关 |
| 绿 | done | 关 |

主路径是本 App 系统通知，不引导第三方通知 App。
