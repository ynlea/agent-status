# Implement — Windows 桌面端（Flutter 复用）

## 执行顺序

### 0. 环境与平台工程

- [ ] 确认本机/CI 具备 Flutter Windows desktop 能力（或文档写明需在 Windows 上构建）
- [ ] `cd mobile && flutter create --platforms=windows .` 生成 `windows/`（不覆盖 lib）
- [ ] `flutter pub get`；解决 Windows 插件兼容
- [ ] 验证：`flutter build windows` 或 `flutter run -d windows` 能起空壳/现有 UI

### 1. 依赖与入口

- [ ] 引入桌面依赖（按 design 选型，如 `window_manager`、`tray_manager`；岛窗插件按调研结果）
- [ ] `main.dart`：Windows 下初始化窗口选项（默认尺寸、最小尺寸、preventClose）
- [ ] 确保非 Windows 路径行为不变

### 2. 桌面壳布局 + 功能对等

- [ ] `MainShell`（或等价）Windows 侧栏导航：首页 / 设备 / 用量 / 设置
- [ ] 默认窗口尺寸偏桌面；内容区按宽布局排版（内边距、列表密度可略疏）
- [ ] 宽屏主从分栏：设备列表+详情；会话列表+详情（窄屏回退整页）
- [ ] 欢迎/配置页：居中单卡，不进侧栏壳
- [ ] 演示模式、配置、首页/设备/用量/设置在 Windows 可走通
- [ ] WebSocket 连接与刷新正常
- [ ] `MonitorBridge` 在 Windows 保持 no-op，不抛错
- [ ] 设置页 Windows 文案：弱化「后台监测」Android 表述
- [ ] Android 底栏路径回归通过

### 3. 托盘 + 关窗

- [ ] 托盘图标（复用现有 app 图标或简化版）
- [ ] 菜单：显示主窗口、退出
- [ ] 关闭主窗 → hide；托盘可 show
- [ ] 退出路径唯一且清理岛窗

### 4. 灵动岛

- [ ] 定义 `IslandViewModel` 过滤/排序/展开规则（对照 PRD + design）
- [ ] 实现岛窗 UI（胶囊 / 展开）与显隐
- [ ] 订阅 `StatusRepository` + 通知开关
- [ ] 点击 → 显示主窗 + 路由到会话
- [ ] 主窗隐藏时岛仍工作
- [ ] 手工验收：confirm/working/done 开关分别生效

### 5. Windows 更新

- [ ] `AppUpdateService`：按平台选择资产名  
  - Android: `qingya-android-release.apk`  
  - Windows: `qingya-windows-setup.exe`
- [ ] 下载后 Windows：`Process.start` 打开安装包；错误文案友好
- [ ] 设置页下载安装流程在 Windows 可走通（可用假 Release 或本地文件测）

### 6. 打包与 CI

- [ ] 本地脚本：Windows 构建 + Inno Setup（或选定工具）→ `qingya-windows-setup.exe`
- [ ] `.github/workflows/release.yml`：增加 `windows-latest` job 构建 Flutter Windows 并打包
- [ ] 上传与 Android APK、Go 二进制同一 Release
- [ ] 文档：`docs/install.md` / README 增加 Windows 客户端说明

### 7. 质量门槛（完成前）

- [ ] Android：现有 `flutter test`（含关键 golden 若环境允许）通过
- [ ] Windows：按 PRD 验收清单手工过一遍
- [ ] 无密钥/证书误提交

## 验证命令（按环境）

```bash
# 共享逻辑
cd mobile && flutter test

# Windows 开发机
cd mobile && flutter run -d windows
cd mobile && flutter build windows --release
```

CI：推送 `v*` tag 后检查 Release 是否含 `qingya-windows-setup.exe` 与 APK。

## 风险文件

| 区域 | 说明 |
|------|------|
| `mobile/lib/main.dart` / `app.dart` | 入口与导航，易影响全平台 |
| `mobile/lib/data/update/app_update_service.dart` | 更新双端逻辑 |
| `mobile/lib/ui/pages/settings_page.dart` | 更新 UI、平台文案 |
| `.github/workflows/release.yml` | 发版 |
| 新建 `lib/data/desktop/*`、`lib/ui/desktop/*` | 桌面专属 |

## 回滚点

1. 平台工程生成后、大改 lib 前：可仅保留 `windows/` 空壳  
2. 托盘/岛接入前：主窗已可运行  
3. CI 上传 Windows 资产前：不影响现有 Android 发版  

## 子任务拆分建议（可选）

若单任务过大，可在 start 后拆 child（依赖写在各 child prd）：

1. `windows-shell` — 平台工程 + 主窗跑通  
2. `windows-tray` — 托盘与关窗  
3. `windows-island` — 灵动岛  
4. `windows-update-ci` — 更新与发版  

默认本任务**单任务顺序执行**，不强制拆分。

## start 前检查

- [x] `prd.md` 需求与验收完整  
- [x] `design.md` 边界与数据流明确  
- [x] `implement.md` 有序清单  
- [ ] 用户确认规划，再 `task.py start`  
