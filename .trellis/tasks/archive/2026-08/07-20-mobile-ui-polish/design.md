# Design — 移动端导航与用量/设置页 UI 打磨

## Boundaries

| 触点 | 文件 | 改什么 |
|------|------|--------|
| 路由 | `mobile/lib/app.dart` | 设备下嵌套会话详情；保留顶层会话路由给首页 |
| 设备会话列表 / 头 | `mobile/lib/ui/pages/devices_page.dart` | push 路径；`_DetailHeader` 高度与文本 |
| 会话详情 | `mobile/lib/ui/pages/session_detail_page.dart` | 返回逻辑视路由而定，优先 `pop` |
| 用量页 | `mobile/lib/ui/pages/usage_page.dart` | 筛选一行；明细标题旁分段；下拉样式 |
| 设置页 | `mobile/lib/ui/pages/settings_page.dart` | `_SettingsValueRow` 对齐 |

不改：`usage_repository` 查询语义、后端、主题 palette 主定义。

## 1. 返回栈

### 现状

```
StatefulShell
  /devices
    /devices/:machineId     ← DeviceDetailPage
/sessions/:machineId/:agent/:sessionId   ← 顶层，与 Shell 平级
```

设备页 `context.push('/sessions/...')` 推到 Shell 外顶层路由时，部分手势返回会丢掉 shell 内嵌套栈，落到 `/devices`。

### 方案

1. 在 `/devices/:machineId` 下增加子路由：
   - path: `sessions/:agent/:sessionId`
   - `parentNavigatorKey: _rootKey`（全屏盖住底栏，与现详情一致）
   - builder 仍用 `SessionDetailPage`
2. 设备会话列表（活跃/空闲卡片）改为：
   - `context.push('/devices/$machineId/sessions/$agent/${Uri.encodeComponent(sessionId)}')`
3. 保留顶层 `/sessions/...`，供首页等入口使用，返回仍 `pop` 到首页。
4. 详情页继续 `context.pop()`，不写死 `go('/devices')`。

兼容：旧深链若仅命中顶层 `/sessions/...` 仍可用；设备路径走嵌套以保证栈。

## 2. 设备详情头

### 现状

- `SizedBox(height: 150)` + 右侧猫图 `128` + 文案区 `right: 120`。
- 版本在「平台 · version」一行 `ellipsis`，下方再有「监测端 version」与「最后心跳」，易被高度裁切。

### 方案

- 去掉过紧固定高度，改为 `minHeight` 或内容自适应 + 底部给猫图留白。
- 版本、最后心跳允许 `maxLines: 2`（或取消 ellipsis 截断），保证全文可读。
- 避免版本重复展示：平台行只保留平台；版本单独一行「监测端 x」完整显示。
- 猫图继续 `Positioned` 右下，文案区保留右侧 inset，避免压字。

## 3. 用量筛选与明细切换

### 现状

- 第一行：时间 + 设备  
- 第二行：渠道 + 明细(groupBy)  
- 明细标题仅文字，无切换  

### 方案

**筛选行（一行三列）**

```
[ 日期 ] [ 设备 ] [ 渠道 ]
```

- 三列 `Expanded` + 更小间距（约 6）。
- `_DropdownBox`：高度约 34–36；字号略减；菜单 `borderRadius`、item padding、`dropdownColor` 跟 `qingya.card`；选中项可用 `primarySoft` 轻提示。

**明细标题行**

```
明细                    [按模型 | 按设备 | 按渠道]
```

- 左侧标题不变。
- 右侧小号 `SegmentedButton`（或等价自定义 chip 段），选项对应现有 `groupBy`: `model` / `machine` / `agent`。
- 样式：比设置页主题切换更矮（visualDensity compact、字号 11–12、padding 收紧）。
- 从顶部筛选移除 groupBy 下拉；`setQuery` 逻辑不变。

## 4. 设置页对齐

### 现状

```dart
Expanded(label) + Flexible(value) + chevron?
```

值短时 `>` 不贴右，多行 `>` 不共线；无 chevron 的版本行也未占满右侧。

### 方案

统一 `_SettingsValueRow`：

```dart
Row(
  children: [
    Text(label),                    // 固有宽度
    SizedBox(width: 12),
    Expanded(
      child: Text(value, textAlign: TextAlign.right, overflow: ellipsis),
    ),
    if (onTap != null) ...[
      SizedBox(width: 6),
      chevron,
    ],
  ],
)
```

- 有 `onTap` 时 chevron 贴右缘，三行共线。
- 版本行无 chevron，值 `Expanded` + `TextAlign.right` 仍右对齐。

## Data flow

无 API 变更。`UsageQueryState.groupBy` 仍由 `usageRepository.setQuery` 驱动 breakdown 请求。

## Tradeoffs

| 选项 | 结论 |
|------|------|
| 详情硬编码 `go('/devices/id')` | 否：破坏首页入口返回 |
| 仅修 Android predictive back | 否：根因是路由树 |
| 设备子路由 + root navigator | 是：栈正确且仍全屏 |
| 筛选改底部 sheet | 否：本轮只压一行 + 美化下拉 |

## Compatibility / Rollback

- 仅 UI/路由；回滚相关 dart 文件即可。
- 无存储迁移。

## Test notes

- 手测：设备→会话列表→详情→手势返回；首页→详情→返回。
- 手测：长版本号、离线最后心跳文案。
- 手测：用量三筛一行、明细切换、浅/深色菜单。
- 手测：设置连接三行 `>` 与版本右对齐。
