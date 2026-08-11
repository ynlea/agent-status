# App 检查更新（GitHub Release）

## Goal

轻芽 App 可检查 GitHub Release 是否有新版本，下载 APK 并调起系统安装。下载源为 GitHub（暂无国内镜像）。

## Requirements

- 设置页可手动「检查更新」，对比 `releases/latest` 的 `tag_name` 与本机版本。
- 资产优先 `qingya-android-release.apk`。
- 有新版本时确认后下载（带进度）并打开系统安装器。
- 网络/无资产失败时中文提示；不静默强制安装；不走 yueya。

## Acceptance Criteria

- [ ] 设置页可检查并区分最新 / 有更新 / 失败
- [ ] 可下载 APK 并进入系统安装流程
- [ ] Android 具备安装未知应用相关声明与 FileProvider
- [ ] 无用户指令不 commit
