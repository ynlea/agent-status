# 手机端深色与浅色模式切换

## Goal

让轻芽 Flutter App 支持用户选择外观模式（跟随系统 / 浅色 / 深色），重启后保持选择，并通过完整颜色 token 化，使浅色/深色页面都不再依赖硬编码浅色。

## Confirmed facts（代码已核实）

- 已有 `QingyaTheme.light()` / `QingyaTheme.dark()`。
- `MaterialApp.router` 目前写死 `themeMode: ThemeMode.system`。
- `AppSettings` / `SharedPreferences` 未持久化主题偏好。
- 设置页暂无外观入口；现有模式为分组卡片 + 开关/值行。
- `QingyaColors.*` 在业务 UI 中大量直接引用（用量、会话详情、设备、任务卡、壳层等）。
- 深色 `ThemeData` 目前较简。
- 设置由 Riverpod `settingsProvider` + SharedPreferences 管理。
- 存在 `prototype_visual_test.dart` 浅色 golden（home / devices / settings / welcome 等）。

## Requirements

### 模式切换

- 支持三种外观：跟随系统、浅色、深色。
- 设置页提供外观分段控件（SegmentedButton / 等效三段选择）：跟随系统 | 浅色 | 深色。
- 切换后立即生效；冷启动后恢复上次选择；默认跟随系统。

### 完整 token 化

- 颜色收敛为可随主题切换的 token（浅色/深色各一套），在现有浅色品牌感上推导深色。
- 业务页面、壳层、通用组件通过 token / Theme 取色，不再直接写死浅色表面色与文字色。
- 完善深色主题：脚手架、卡片、文字、边框、分割线、输入、按钮、导航、状态色等主表面与浅色对称可用。
- 主路径页面深色可读、可导航、层级清楚。

## Acceptance Criteria

- [ ] 设置页可用分段控件选择：跟随系统 / 浅色 / 深色。
- [ ] 选择后全局 `themeMode` 立即变化。
- [ ] 重启 App 后仍为上次选择；默认跟随系统。
- [ ] 浅色/深色均有完整颜色 token；深色覆盖主表面与状态色。
- [ ] 主路径页面（首页、设备、设置、会话详情、用量、欢迎/配置、底部导航壳）深色下不因硬编码浅色而发白或文字看不清。
- [ ] 浅色模式相对当前无明显视觉回归；设置页变更后更新相关 golden（若测试失败）。
- [ ] 主题偏好持久化键与模型字段命名清晰。

## Out of scope

- 自定义强调色 / 多套主题包。
- 服务端同步主题偏好。
- 启动闪屏与系统主题深度定制。
- 独立设计稿驱动的全新视觉重设计。
- 强制要求补齐全套深色 golden 截图（可选增强，非本任务阻断项）。

## Decisions

| 项 | 结论 |
|----|------|
| 范围 | C：完整 token 化 + 三选一模式切换与持久化 |
| 模式选项 | 跟随系统 / 浅色 / 深色 |
| 默认 | 跟随系统 |
| 深色色板 | 在现有浅色品牌色上推导 |
| 设置交互 | 分段控件（Segmented） |

## Open questions

- 无阻断项。进入 design / implement 后若实现细节冲突再回改本 PRD。
