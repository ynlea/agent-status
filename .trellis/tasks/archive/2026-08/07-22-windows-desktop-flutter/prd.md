# Windows 桌面端（Flutter 复用）

## Goal

在现有 Flutter「轻芽」只读客户端基础上，交付完整功能的 Windows 桌面端，并提供**灵动岛样式**的状态通知体验，让用户在 PC 上也能及时看到 Agent 会话变化。

## Confirmed facts（仓库已证实）

- 客户端在 `mobile/`，Flutter 工程名 `qingya`，当前只有 `android/`、`ios/`，没有 `windows/` 平台目录。
- 业务与 UI 主要在 `lib/`（欢迎/配置、首页会话、设备、用量、设置、会话详情、Provider 相关页；REST + WebSocket；本地设置）。
- 服务端是 Go + SQLite，API 契约在 `docs/api.md` / `api/openapi.yaml`；只读查看侧无需改协议即可对接。
- 通知相关现有能力：
  - 设置项：总开关 + `confirm` / `working` / `done` 三类通知。
  - Android 侧经 `MonitorBridge` 同步到前台服务与常驻通知；非 Android 直接跳过。
  - 状态图标素材已有：`ic_notify_confirm/working/done`。
  - 桌面端尚无“灵动岛 / 悬浮岛”实现。
- 检查更新目前只支持 Android APK 安装（`AppUpdateService` + `qingya/updater` 通道）。
- 发版：`.github/workflows/release.yml` 已有 Go 多平台与 Flutter Android APK；尚无 Windows Flutter 产物。
- App 主定位是**只读查看**；本机上报由独立 `cmd/monitor` 负责。

## Product decisions

| 决策 | 结论 |
|------|------|
| 技术栈 | Flutter Windows，复用 `lib/` |
| v1 范围档位 | **全功能，不做裁剪版 MVP** |
| 通知形态 | **灵动岛样式**（自定义悬浮岛 UI） |
| 灵动岛出现规则 | **有状态时顶栏常驻胶囊；变化时展开**。无目标状态收起/隐藏；点展开区进入对应会话 |
| 关窗行为 | **关主窗口 = 缩到托盘**；进程与灵动岛继续；仅托盘「退出」才结束进程 |
| 本机上报 | **不做 monitor 内嵌/托管**；桌面端只读；本机上报仍用独立 `cmd/monitor` |
| Windows 更新 | **应用内检查 → 自动下载安装包 → 调起安装程序** |
| 版本号 | **与 Android 共用** `pubspec` 的 version/build；同一 GitHub Release 挂两端产物 |
| 主窗 UI 布局 | **桌面风重排**：侧栏导航 + 更宽内容区；色板/组件语言仍沿用轻芽 |
| 列表/详情 | **关键列表主从分栏**（设备/会话等）；窄屏回退单页堆栈 |

## Requirements

### 功能对等（与现有轻芽客户端对齐）

- 欢迎 / 配置服务地址与密钥、演示模式
- 首页活跃会话、设备列表与详情、用量、设置、相关业务页
- REST + WebSocket 实时刷新；设置项（含三类通知开关）可用
- 桌面端可正常构建、安装/运行于 Windows

### 桌面增强

- 窗口：合理默认尺寸、可缩放（桌面布局默认更宽，见 design）
- **主窗布局（Windows）**
  - 导航/组件：沿用轻芽暖色、圆角卡片、状态色与现有素材
  - 导航：侧栏主导航（首页 / 设备 / 用量 / 设置），替代底栏 Tab 在桌面的主形态
  - 内容区：更宽可用宽度
  - 关键列表（设备、会话相关）：宽屏主从分栏（左列表右详情）；窄于断点时回退现有整页堆栈
  - Android 仍保持现有底栏与手机布局，不强制跟桌面侧栏
- **关窗 / 托盘**
  - 关闭主窗口：隐藏到托盘，不退出
  - 托盘：显示主窗口、退出
  - 进程在托盘驻留期间继续收 WebSocket，并按规则维护灵动岛
- **灵动岛通知**
  - 无目标状态：收起或隐藏
  - 有 `confirm` / `working` / `done`（且对应通知开关开启）：显示顶栏胶囊
  - 状态变化或需确认：展开详情
  - 点击可进入对应会话 / 拉起主窗口相关页
  - 主窗口隐藏时岛仍可按规则显示
- 检查更新（Windows）
  - 对齐 GitHub Release 检查能力
  - 识别 Windows 安装包资产（如 `qingya-windows-setup.exe`）
  - 有新版本时自动下载，下载完成后调起安装程序

### 平台适配

- Android 专属路径在 Windows 上有明确行为（桌面等价能力或安全降级）
- 不破坏现有 Android 构建与测试

## Acceptance Criteria

- [ ] Windows 可构建并启动轻芽桌面端，完成配置后连上服务，首页/设备/用量/设置可用
- [ ] Windows 主窗为侧栏导航 + 宽内容区，视觉仍识别为轻芽（色板/卡片/状态色）
- [ ] 宽屏下设备/会话等关键列表支持主从分栏；窄屏回退单页
- [ ] Android 底栏手机布局不被桌面侧栏方案破坏
- [ ] 演示模式在 Windows 可用
- [ ] WebSocket 状态变化能驱动界面与灵动岛刷新
- [ ] 通知设置开关生效于灵动岛展示
- [ ] 灵动岛：有状态常驻胶囊、变化展开、无状态收起/隐藏，点击可导航到相关会话
- [ ] 系统托盘可用（显示主窗口、退出）
- [ ] 关闭主窗口后进程不退出；托盘可重新打开主窗口；真正退出仅通过托盘「退出」
- [ ] 主窗口隐藏时，灵动岛仍可按规则显示并响应状态变化
- [ ] Android 端现有能力不被本次改动破坏
- [ ] 设置中可检查更新；发现新版本后自动下载 Windows 安装包并调起安装程序
- [ ] CI/发版链路可产出与 Android 同 tag 的 Windows 安装包资产

## Out of scope（本任务）

- 改用非 Flutter 技术栈
- 无必要地改服务端 API 契约
- macOS / Linux 桌面
- 将 `cmd/monitor` 内嵌进桌面端，或在桌面端内提供本机会话扫描/上报
- MSIX 商店自动更新、静默覆盖运行中 exe

## Open questions

（产品与 UI 布局决策已收敛；实现细节见 `design.md` / `implement.md`。）


## Notes

- 用户审过 `prd.md` / `design.md` / `implement.md` 后再 `task.py start`。
