# Design — Windows 桌面端（Flutter 复用）

## 1. 边界

| 层 | 职责 |
|----|------|
| 复用 `mobile/lib` | 页面、主题、Riverpod、REST/WS、设置、业务模型 |
| Windows 平台壳 | `windows/` 工程、窗口生命周期、托盘、启动参数 |
| 灵动岛 | 独立置顶小窗 + 订阅 `StatusRepository` 快照，按通知开关过滤 |
| 更新 | 扩展 `AppUpdateService`：按平台选资产、Windows 下下载后 `Process.start` 调起安装包 |
| 发版 | Release workflow 增加 Windows runner 构建 Flutter + 打包安装器 |
| 不做 | 本机 monitor 扫描/上报；改 API 契约；macOS/Linux 桌面 |

## 2. 架构概览

```
┌─────────────────────────────────────────────────────────┐
│  同一 Flutter 进程                                        │
│  ┌──────────────┐   ┌──────────────┐   ┌─────────────┐  │
│  │ 主窗口        │   │ 灵动岛窗口    │   │ 系统托盘     │  │
│  │ 现有路由/页面  │   │ 胶囊/展开 UI  │   │ 显示/退出    │  │
│  └──────┬───────┘   └──────┬───────┘   └──────┬──────┘  │
│         │                  │                   │         │
│         └──────────┬───────┴───────────────────┘         │
│                    ▼                                     │
│         StatusRepository + settingsProvider              │
│         (REST / WebSocket / demo)                        │
└─────────────────────────────────────────────────────────┘
```

- **单进程多窗口**：主窗口 + 灵动岛窗口共享同一 Dart isolate 与 Riverpod 状态，关主窗时只 `hide`，不 `exit`。
- 灵动岛必须在主窗隐藏后仍可见 → **不能**只做主窗内 Overlay；需桌面多窗口（推荐 `desktop_multi_window` 或官方 `window_manager` + 子窗方案；实现阶段以能置顶、无边框、可点透/可点中为准选型）。
- 托盘推荐 `tray_manager` + `window_manager`（Flutter Windows 社区常用组合）。

## 3. 数据流

### 3.1 状态 → 灵动岛

1. `StatusRepository` 维持 `StatusSnapshot`（与首页相同来源）。
2. 灵动岛控制器派生 `IslandViewModel`：
   - 输入：`activeSessions` + `notifyConfirm/Working/Done` + 总开关语义（与设置页一致：三类开关）。
   - 过滤：仅保留开关打开且状态 ∈ {confirm, working, done} 的会话。
   - 排序：沿用现有 `sortActiveSessions` / `SessionState.sortRank`（confirm > working > done）。
   - **胶囊摘要**：取最高优先级 1 条（或 N 条聚合文案，如「2 个待确认」）；实现时优先 1 条高优 + 角标数量。
3. **展开时机**：过滤结果集合相对上一拍有新增/状态升级（尤其进入 confirm），或用户点击胶囊。
4. **收起/隐藏**：过滤结果为空 → 隐藏岛窗；展开后超时或点击外部/再次点击可收为胶囊（交互默认：展开约 5–8s 后收回胶囊，confirm 可更久或直到用户点开）。

### 3.2 点击岛 → 主窗导航

1. 显示主窗口（`window_manager.show` + focus）。
2. 通过已有 `GoRouter` 跳到会话详情路由：  
   `/sessions/:machineId/:agent/:sessionId` 或设备下嵌套路由（与 `app.dart` 现有路径对齐）。
3. 岛可保持胶囊或暂隐，不强制关岛。

### 3.3 关窗 / 托盘

| 用户动作 | 行为 |
|----------|------|
| 点主窗关闭 | `preventClose` → hide 主窗；进程继续；岛按规则继续 |
| 托盘「显示轻芽」 | show + focus 主窗 |
| 托盘「退出」 | 关闭岛窗、托盘，再 `exit(0)` |
| 系统注销/关机 | 随进程退出（无特殊保活） |

### 3.4 更新

| 平台 | 资产名（约定） | 安装 |
|------|----------------|------|
| Android | `qingya-android-release.apk`（现有） | MethodChannel `qingya/updater` |
| Windows | `qingya-windows-setup.exe` | 下载到临时目录后 `Process.start(path)` 调起 |

- `checkLatest`：仍读 GitHub `/releases/latest`；按当前平台在 `assets[]` 中匹配资产名。
- 版本比较：继续用现有 semver 逻辑；`package_info_plus` 的 version 与 tag 对齐（共用 pubspec）。
- 安装器形态：第一期用 **Inno Setup 或等价** 打出单文件 setup.exe（也可用 `flutter build windows` 目录 + 脚本打包）；CI 产出文件名必须稳定为约定资产名。

## 4. 模块切分（建议落点）

```
mobile/lib/
  main.dart                 # 平台分支：Windows 初始化 window/tray/island
  data/update/app_update_service.dart  # 平台资产 + Windows install
  data/desktop/             # 新建（仅非 Web/移动引用）
    window_controller.dart  # 关窗拦截、show/hide
    tray_controller.dart
    island_controller.dart  # 显隐、展开、导航回调
    island_models.dart
  ui/desktop/
    island_window_app.dart  # 岛窗根组件（胶囊/展开）
```

- Android 路径保持：`MonitorBridge` 仅 Android；Windows 不调用。
- 设置页「后台监测」文案在 Windows 上改为说明：通知由灵动岛承担，无需 Android 前台服务（避免误导）。

## 5. UI 约定

### 5.1 主窗布局（Windows = 桌面风）

```
┌────────┬──────────────────────────────────────┐
│ 轻芽    │  页面标题 / 可选工具条                 │
│ ───    ├──────────────────────────────────────┤
│ 首页    │                                      │
│ 设备    │         内容区（更宽）                  │
│ 用量    │                                      │
│ 设置    │                                      │
└────────┴──────────────────────────────────────┘
```

- **壳层**：Windows 使用侧栏 `NavigationRail` 风格（图标 + 文案），替换 `MainShell` 底栏在桌面的呈现；实现上建议 `MainShell` 按 `Platform.isWindows`（或宽度断点）分支，避免复制整棵路由树。
- **默认窗口**：约 `1100×720`，最小约 `880×600`（实现时可微调）。
- **视觉**：`QingyaPalette`、卡片圆角、阴影、状态色、现有 PNG 素材全部复用；侧栏背景用 `scaffold`/`card`，选中态用 `primarySoft` + 主色指示条。
- **欢迎/配置页**：可仍居中单卡（不必侧栏），配置完成后再进带侧栏的主壳。
- **Android**：不改底栏信息架构。

### 5.2 列表与详情（主从分栏）

- **宽屏**（建议断点 ≥ 900px 内容区，或窗口宽 ≥ 1000）：  
  - 设备：左 `DevicesPage` 列表，右 `DeviceDetailPage`；未选中时右侧空态「选择一台设备」。  
  - 会话：从首页或设备进入时，尽量左列表右 `SessionDetailPage`（与现有路由参数对齐，可用 shell 内二级路由或本地 selectedId，避免拆掉 go_router）。  
- **窄屏**：保持现有 push 整页堆栈，与 Android 信息架构一致。  
- **设置 / 用量 / 欢迎**：不分栏；用量可适当加宽图表/表格区域。

### 5.3 灵动岛

- 位置：主屏顶部水平居中（可后续记忆偏移；v1 固定）。
- 形态：胶囊，圆角；左侧状态色点或现有 notify 图标，右侧短文案（设备名 / agent / 状态）。
- 展开：加宽显示会话标题或 machine + agent；点击进详情。
- 动画：宽度/高度缓动。
- 主题：复用 `QingyaPalette`，与主窗一致。

## 6. 兼容与风险

| 风险 | 缓解 |
|------|------|
| 多窗口插件与 Flutter 版本不兼容 | 实现前锁定插件版本；备选「单主窗 + 无边框 alwaysOnTop 第二 Flutter 引擎」调研记录在 research |
| 关窗误退出 | `window_manager.setPreventClose(true)` + 单测/手工清单 |
| 岛窗抢焦点 | 配置为工具窗/不抢焦点（Windows WS_EX_NOACTIVATE 类行为，按插件能力设置） |
| CI 无 Windows 签名证书 | 第一期可未签名 setup（与早期 Android debug 类似）；文档标明 SmartScreen 提示 |
| 改 lib 影响 Android | 平台 `if (Platform.isWindows)` 隔离；跑现有 golden/unit |

## 7. 回滚

- 功能开关：可用编译期或设置项暂时禁用岛/托盘（若联调不稳）。
- 发版：Release 不上传 Windows 资产即不影响 Android 用户。
- 代码：桌面模块集中在 `data/desktop` + `ui/desktop`，删除/不链 windows 目标即可收缩。

## 8. 与 PRD 映射

- 功能对等 → 启用 `windows` 目标 + 冒烟全页面  
- 托盘/关窗 → `window_controller` + `tray_controller`  
- 灵动岛 → `island_*` + 状态派生  
- 更新 → `AppUpdateService` 扩展 + CI 资产  
- 共用版本 → 单一 pubspec；workflow 同 tag  
