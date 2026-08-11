# 技术设计：手机端深色与浅色模式切换

## 边界

- 仅改 `mobile/` Flutter 客户端。
- 不改后端、不改 Web。
- 外观偏好只存本地 SharedPreferences。

## 架构

```
AppSettings.themeModePreference
        │
        ▼
SettingsStore (SharedPreferences)
        │
        ▼
settingsProvider ──► QingyaApp MaterialApp.router.themeMode
        │
        ▼
QingyaTheme.light() / dark()
  + ThemeExtension<QingyaPalette>  （或等价：Brightness 取色 API）
        │
        ▼
页面 / 组件 通过 context.qingya 或 Theme 取 token
```

## 数据与契约

### 偏好枚举

建议在 domain 层增加与 Flutter `ThemeMode` 可互转的偏好：

- 存储值：`system` | `light` | `dark`（字符串，SharedPreferences）
- 键名：`theme_mode`（建议）
- 默认：`system`
- 非法/缺失 → 回落 `system`

`AppSettings` 增加字段（命名示例）：`themeMode`（内部可用枚举 `AppThemeMode`，避免与 Flutter `ThemeMode` 混淆时再命名）。

`SettingsStore._load` / `save` 读写该键；`copyWith` 同步支持。

### MaterialApp

`QingyaApp`：

- `theme` / `darkTheme` 仍为 light/dark ThemeData
- `themeMode` 改为 `ref.watch(settingsProvider.select(...))` 映射到 `ThemeMode`

### 颜色 Token

现状：`QingyaColors` 为静态浅色常量，页面直接引用。

目标：

1. **语义 token 表**（浅/深各一套），至少覆盖现有常量职责：
   - scaffold / card / primary / primaryDark / primarySoft
   - device / deviceSoft
   - textPrimary / textSecondary
   - confirm / confirmSoft / working / workingSoft / done / doneSoft / idle / idleSoft
   - online / offline
   - divider / navInactive / shadow / border
2. **挂载方式（推荐）**：`ThemeExtension<QingyaPalette>` 挂到 light/dark 的 `ThemeData.extensions`，页面用 `context.qingya`（extension on BuildContext）取色。
3. **兼容策略**：保留 `QingyaColors` 名称空间若迁移成本高，可改为「仅 light 静态别名 + 标注弃用」，但验收要求主路径页面不得再依赖浅色静态表面色；实现阶段优先一次性迁到 extension。
4. **深色推导原则**：
   - 表面：深灰褐系（与现有 dark scaffold `#1C1917` / surface `#2A2624` 对齐扩展）
   - 主文：浅暖灰白；次文：降对比但可读
   - 品牌 primary / device：尽量保持识别色，soft 背景改为低饱和深底上的 tint
   - 状态色：保持语义色相，调整亮度以保证深底对比

### 设置 UI

- 设置页新增「外观」分组（或放在合适位置）。
- 使用 Material 3 `SegmentedButton<AppThemeMode>`（或现有风格下的三段选择）展示：跟随系统 / 浅色 / 深色。
- `onSelectionChanged` → `settingsProvider.notifier.save(settings.copyWith(themeMode: ...))`。
- 分段控件自身颜色走 token，避免写死浅色。

## 迁移面（文件级）

高引用优先：

- `theme/qingya_theme.dart` — token + ThemeData 完善
- `app.dart` — themeMode 接线
- `domain/models.dart` + `data/prefs/settings_store.dart` — 偏好
- `ui/pages/settings_page.dart` — 分段控件
- 页面：`usage_page` / `session_detail_page` / `devices_page` / `home_page` / `welcome_page` / `settings_page`
- 组件：`task_card` / `main_shell` / `prototype_widgets` / `status_dot` / `empty_state`

## 兼容与回归

- 未升级用户：无 `theme_mode` 键 → 跟随系统（与今相同）。
- 浅色：token 值应对齐当前 `QingyaColors`，避免浅色漂移。
- Golden：设置页布局会变；浅色 golden 需在实现后按需 `--update-goldens` 并同步 docs 截图（若仓库流程要求）。

## 权衡

| 方案 | 取舍 |
|------|------|
| ThemeExtension | 类型安全、随 Theme 切换；改动面大但符合范围 C |
| 仅 ThemeMode + 零星 Theme.of | 改得少，深色仍会漏硬编码 |
| 全局 Riverpod 下发 palette | 可工作，但绕开 Material Theme，组件测试与系统亮度联动更绕 |

选定：ThemeExtension + settings 持久化 ThemeMode。

## 回滚

- 偏好键可忽略；删字段后默认 system。
- 主题相关提交集中在 mobile 主题与 UI，回滚单 commit 或还原上述文件即可。
