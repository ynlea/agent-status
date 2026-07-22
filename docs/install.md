# 一键安装与本机管理

轻量二进制安装（**不走 Docker**）。支持交互式菜单与非交互参数。

> 仓库需为 **Public**，并已发布 GitHub Release 资产后，远程一键命令才可用。  
> 开发联调可用 `--local-bin` 指向本机编译产物。

## 目录布局

| 平台 | 安装根目录 |
|------|------------|
| Linux | `~/.local/share/agent-status` |
| Windows | `%LOCALAPPDATA%\agent-status` |

子目录：`bin/`、`config/`、`data/`、`logs/`、`state/`（Windows pid）。

## Linux

### 远程一键（发布后）

```bash
curl -fsSL https://raw.githubusercontent.com/ynlea/agent-status/main/scripts/install.sh | bash
```

### 本地脚本

```bash
chmod +x scripts/install.sh scripts/release-build.sh

# 开发：先编再装
./scripts/release-build.sh
./scripts/install.sh install --role all --key dev-secret \
  --server-url http://127.0.0.1:29125 --local-bin ./dist/release --yes
```

### 常用命令

```bash
./scripts/install.sh status --role all
./scripts/install.sh start|stop|restart --role server
./scripts/install.sh enable|disable --role monitor
./scripts/install.sh config get --role monitor
./scripts/install.sh config set --role monitor server_url=http://10.0.0.2:8080
./scripts/install.sh init-agents
./scripts/install.sh uninstall --role monitor          # 保留文件
./scripts/install.sh uninstall --role all --purge      # 删除安装目录
```

非交互安装：

```bash
./scripts/install.sh install --role server --key "$KEY" --addr :29125 --yes
./scripts/install.sh install --role monitor --server-url "http://127.0.0.1:29125" --key "$KEY" --yes
```

Linux 常驻：`systemctl --user` 单元  
`agent-status-server.service` / `agent-status-monitor.service`。

无图形登录时若开机不自启，可查阅 `loginctl enable-linger $USER`。

## Windows

### 远程一键（发布后）

```powershell
irm https://raw.githubusercontent.com/ynlea/agent-status/main/scripts/install.ps1 | iex
```

### 本地

```powershell
.\scripts\install.ps1 install -Role monitor -ServerUrl http://127.0.0.1:29125 -Key dev-secret -LocalBin .\dist\release -Yes
.\scripts\install.ps1 status -Role all
.\scripts\install.ps1 stop -Role monitor
.\scripts\install.ps1 start -Role monitor
.\scripts\install.ps1 enable -Role monitor
.\scripts\install.ps1 config get -Role monitor
.\scripts\install.ps1 init-agents
.\scripts\install.ps1 uninstall -Role all
```

Windows 常驻：进程 + 可选「登录时」计划任务（`AgentStatusServer` / `AgentStatusMonitor`），**不是** Windows Service。

## 监测端与 Agent 初始化

安装监测端后会探测：

- Claude Code：`claude` 在 PATH 或 `~/.claude` 存在 → 调用  
  `agent-status-monitor --init --claude --config <安装目录>/config/monitor.json`
- Codex：仅探测并保持 monitor 配置中的 file-watch，不改 Codex 全局配置

跳过初始化：`--no-init-agents` / `-NoInitAgents`。

## 发布资产

### CI 自动发版（推荐）

推送符合 `v*` 的 tag 后，GitHub Actions（`.github/workflows/release.yml`）会：

1. **Go**：在 Ubuntu 上交叉编译 Linux/Windows 的 server、monitor  
2. **Flutter Android**：在 Ubuntu 上编译 `qingya-android-release.apk`  
3. **Flutter Windows**：在 `windows-latest` 上编译桌面端并打包 `qingya-windows-setup.exe`  
4. 汇总上传到同一 GitHub Release  

```bash
# 确保 main 已包含 scripts/、mobile/ 与 workflow
git tag v0.1.0
git push origin v0.1.0
# 在仓库 Actions / Releases 页面查看结果
```

说明：当前 Android release 使用 **debug 签名**（与工程 gradle 配置一致），便于无 keystore 的 CI；正式上架商店前需换成正式签名。iOS 未纳入本 workflow（需要 macOS runner 与证书）。

### 本机手动

```bash
./scripts/release-build.sh
# 产物在 dist/release/，含 sha256sums.txt
gh release create v0.1.0 dist/release/* --generate-notes
```

资产名：

- `agent-status-server-linux-amd64` / `arm64`
- `agent-status-monitor-linux-amd64` / `arm64`
- `agent-status-server-windows-amd64.exe`
- `agent-status-monitor-windows-amd64.exe`
- `qingya-android-release.apk`
- `qingya-windows-setup.exe`（轻芽 Windows 桌面端安装包）
- `sha256sums.txt`（仅 Go 产物校验和；客户端安装包另附）

### 轻芽 Windows 桌面端

- 与 Android 共用 `mobile/pubspec.yaml` 版本号；同一 GitHub Release 挂两端产物。
- 应用内「检查更新」会匹配资产名 `qingya-windows-setup.exe`，下载后调起安装程序。
- 本机打包（需 Windows + Flutter + 可选 Inno Setup 6）：

```powershell
cd mobile
.\scripts\package_windows.ps1
```

- 关闭主窗口会缩到系统托盘，进程与灵动岛继续；仅托盘「退出」结束进程。
- 桌面端只读查看，本机 Agent 上报仍使用独立 `agent-status-monitor`。

## 与手动部署的关系

- Docker / `go run` 手动路径仍见 `docs/deploy.md`。
- 安装器只管理自己安装根目录下的二进制与配置，不会删除你手动放在仓库目录里的 `monitor.json`。
