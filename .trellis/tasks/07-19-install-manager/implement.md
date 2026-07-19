# Implement: install-manager

## Ordered checklist

### 1. Release 构建

- [x] 新增 `scripts/release-build.sh`：交叉编译 Linux amd64/arm64 + Windows amd64
- [x] 产出 `sha256sums.txt`
- [x] 文档说明 `gh release create`（仓库改 Public 后）
- [x] GitHub Actions：`.github/workflows/release.yml`（push `v*` tag：Go 交叉编译 + Flutter Android APK 并发版）

### 2. Linux 安装器 `scripts/install.sh`

- [x] 参数解析与子命令
- [x] 架构检测、Release / `--local-bin`、布局
- [x] server.env / monitor.json + systemd user
- [x] Agent 探测 + `--init --claude`
- [x] 交互 + `--yes`；持久化 manager 到安装目录

### 3. Windows 安装器 `scripts/install.ps1`

- [x] 命令语义对齐
- [x] 下载 / LocalBin、pid 启停、计划任务
- [x] 配置、探测、Claude init、持久化 manager

### 4. 文档

- [x] `docs/install.md` + 更新 `docs/deploy.md` / `README.md`

### 5. 验证

- [x] Linux：`--local-bin` 非交互装 server，healthz ok，status/stop/uninstall
- [ ] Windows 实机（本环境未跑）
- [ ] 正式 Release 下载路径（待 Public + 发版）

## Validation commands

```bash
# 本地模拟（可用 file:// 或手动放入 bin 后测 manage 子命令）
bash -n scripts/install.sh
shellcheck scripts/install.sh   # 若环境有

# 功能（需 Public Release 或 --bin-dir 本地模式；实现时可加 --local-bin 便于开发）
./scripts/install.sh install --role server --key test-key --yes
./scripts/install.sh install --role monitor --server-url http://127.0.0.1:8080 --key test-key --yes
./scripts/install.sh status --role all
./scripts/install.sh stop --role monitor
./scripts/install.sh start --role monitor
```

```powershell
powershell -NoProfile -File scripts\install.ps1 install -Role monitor -ServerUrl http://127.0.0.1:8080 -Key test-key -Yes
powershell -NoProfile -File scripts\install.ps1 status -Role monitor
```

```bash
# 现有回归：monitor Claude init 仍通过
go test ./cmd/monitor/...
go test ./...
```

## Risky points / rollback

| 风险 | 处理 |
|------|------|
| 私有仓 curl 404 | 发布清单：先 Public 再宣传一键命令 |
| systemd 用户会话 | 文档 linger；status 提示 inactive 原因 |
| Windows 杀软拦下载 | 文档说明；可用手动解压到安装目录 |
| hooks 写错路径 | 只调用已安装 abs 路径；装完再 init |
| 升级覆盖配置 | 默认保留；备份时间戳 |

回滚：`uninstall` 停服务；恢复 `config/*.bak-*` 与 `bin/*.bak`。

## Dev convenience（建议）

- 安装器支持 `--local-bin DIR`：跳过下载，用本地编译产物联调（不进入用户文档主路径）。

## Before `task.py start`

- [x] prd / design / implement 已写
- [ ] 用户审阅通过
- [ ] （可选）仓库改为 Public 的时机与用户确认
