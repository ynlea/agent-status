# 轻芽（Qingya）Flutter 客户端

按 `source/原型图.png` 重做的只读监控 App：首页活跃会话 / 设备 / 设置。

界面示意见仓库根目录 README 的「轻芽界面预览」（`docs/screenshots/`）。更新截图：

```bash
# 需本机有 test/fonts/NotoSansCJK-SC-Regular.otf（见 test/prototype_visual_test.dart）
flutter test test/prototype_visual_test.dart --update-goldens
cp test/goldens/welcome.png ../docs/screenshots/qingya-welcome.png
cp test/goldens/home.png ../docs/screenshots/qingya-home.png
cp test/goldens/devices.png ../docs/screenshots/qingya-devices.png
cp test/goldens/device_detail.png ../docs/screenshots/qingya-device-detail.png
cp test/goldens/settings.png ../docs/screenshots/qingya-settings.png
```

## 运行

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd mobile
flutter pub get
flutter run
```

### Windows 桌面

```powershell
cd mobile
flutter config --enable-windows-desktop
flutter pub get
flutter run -d windows
# 或 release 构建 + 安装包
.\scripts\package_windows.ps1
```

- 侧栏导航 + 宽屏主从分栏；关主窗缩到托盘，灵动岛按通知开关展示。
- 检查更新资产名：`qingya-windows-setup.exe`（与 Android 共用 pubspec 版本）。
- 本机 Agent 上报请用独立 monitor，桌面端只读。

首次进入可点 **「先用演示数据看看」** 预览 UI；或 **开始配置** 填写服务地址与密钥。

接 mock：

```bash
# 仓库根目录
go run ./cmd/mock -addr :8080 -key dev-secret
# App 设置：http://<主机IP>:8080  +  dev-secret
```

## 素材

来自 `source/ui-chroma/flutter_assets/`，已拷入 `assets/images/`。

## 结构

- `lib/theme` — 暖色 Theme
- `lib/ui` — 页面与组件
- `lib/data` — REST / WS / 本地配置
