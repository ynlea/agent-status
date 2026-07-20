# Implement — 移动端导航与用量/设置页 UI 打磨

## Checklist

1. [x] **路由** — `app.dart`：在 `/devices/:machineId` 下增加 `sessions/:agent/:sessionId`（`parentNavigatorKey: _rootKey`）；保留顶层 `/sessions/...`。
2. [x] **设备列表 push** — `devices_page.dart` 活跃/空闲 `TaskCard` 改为 push `/devices/$id/sessions/...`。
3. [x] **详情返回** — `session_detail_page` 仍 `pop`。
4. [x] **设备头** — `_DetailHeader` 自适应高度；平台/版本/心跳可读，去重复截断。
5. [x] **用量筛选** — 日期/设备/渠道同一行；美化 `_DropdownBox` 与菜单。
6. [x] **用量明细切换** — 移除顶部 groupBy 下拉；明细标题右侧小号分段（model/machine/agent）。
7. [x] **设置对齐** — `_SettingsValueRow`：值 Expanded 右对齐，chevron 贴右。
8. [x] **检查** — `dart analyze` 无 issue（本机无真机手测）。

## Validation

```bash
cd mobile && dart analyze lib/app.dart lib/ui/pages/devices_page.dart lib/ui/pages/usage_page.dart lib/ui/pages/settings_page.dart lib/ui/pages/session_detail_page.dart
```

可选：`flutter test`（若环境可用）。

## Review gates

- 返回栈：设备路径与首页路径分开验证。
- 用量：改 groupBy 只刷新明细，不误清筛选。
- 设置：三行 chevron 目测共线。

## Rollback

还原上述 5 个 dart 文件即可。
