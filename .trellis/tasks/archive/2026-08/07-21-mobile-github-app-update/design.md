# Design: GitHub App 更新

## Flow

```
设置页「检查更新」
  → GET https://api.github.com/repos/ynlea/agent-status/releases/latest
  → 解析 tag_name、assets[].name/browser_download_url
  → 与 PackageInfo.version 比 semver（忽略前缀 v）
  → 已最新：SnackBar / 行内提示
  → 有更新：对话框确认 → 下载到 app 缓存目录 → 调系统安装
```

## Version compare

- 规范化：去掉前导 `v`/`V`，按 `major.minor.patch` 数字段比较；段数不足补 0。
- 本机 buildNumber 不参与「是否更新」判断（Release 以 versionName/tag 为准）。

## Download

- 目录：`getTemporaryDirectory()/updates/qingya-<tag>.apk`
- `http.Client` 流式写入 + 进度回调（received/total）。
- Header：`User-Agent: qingya-android`；Accept 默认。
- 不强制校验 sha256（Release 的 sha256sums 不含 APK）；后续可扩展。

## Install (Android)

- 权限：`REQUEST_INSTALL_PACKAGES`
- `FileProvider`：`authority = ${applicationId}.fileprovider`，paths 覆盖 cache/files
- MethodChannel `qingya/updater`：`installApk(path)` → `ACTION_VIEW` + `FLAG_GRANT_READ_URI_PERMISSION`
- 若未授权安装未知应用：跳转 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES`

## UI

- 设置页「关于」或版本行旁：检查更新按钮/可点行。
- 状态：空闲 / 检查中 / 下载中(进度) / 错误文案。

## Files

- `mobile/lib/data/update/app_update_service.dart` — API + 下载 + 版本比较
- `mobile/lib/ui/pages/settings_page.dart` — 入口
- `mobile/android/.../AndroidManifest.xml` — 权限 + FileProvider
- `mobile/android/.../file_paths.xml`
- `mobile/android/.../MainActivity.kt` — MethodChannel 安装
- `pubspec.yaml` — `path_provider`
