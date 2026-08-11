# 实施计划：手机端深色与浅色模式切换

## 顺序清单

1. **Domain + 持久化**
   - `AppSettings` 增加主题偏好字段与 `copyWith`
   - `SettingsStore` 读写 `theme_mode`，默认 system
   - 枚举 ↔ `ThemeMode` 映射小工具

2. **Token 与 Theme**
   - 定义 `QingyaPalette`（ThemeExtension）浅/深两套
   - 浅色 token 对齐现有 `QingyaColors`
   - 深色 token 按 design 原则推导并补全
   - `QingyaTheme.light/dark` 挂 extension，补全 AppBar / Input / Switch / Divider / Nav 等
   - `BuildContext` 扩展：`qingya` 取 palette

3. **App 接线**
   - `QingyaApp`：`themeMode` 从 `settingsProvider` 读取

4. **设置 UI**
   - 设置页「外观」+ `SegmentedButton` 三选一
   - 保存后立即反映

5. **页面/组件迁移**
   - 按引用量迁移：usage → session_detail → devices → task_card → shell → 其余
   - 将 `QingyaColors.xxx` 表面/文字/边框改为 `context.qingya.xxx` 或 Theme 等价物
   - 删除或收敛无用的浅色硬编码

6. **验证**
   - `flutter analyze`（mobile）
   - `flutter test`（含 widget / prototype_visual；失败则更新浅色 golden）
   - 手动或测试覆盖：system/light/dark 切换与冷启动恢复

## 验证命令

```bash
cd mobile
flutter analyze
flutter test
# 若 golden 因设置页变更失败：
# flutter test test/prototype_visual_test.dart --update-goldens
```

## 风险点

- 用量页 / 会话详情色值最多，漏迁会导致深色局部发白。
- 浅色 token 漂移会破坏 golden 与品牌一致性——浅色数值必须对齐现状。
- `SegmentedButton` 样式需与现有卡片风格协调，避免默认 Material 突兀。

## 回滚点

- 完成步骤 1–3 后可独立回退偏好；步骤 5 前深色仍可能不完整。
- 步骤 5 大面积替换后应用单任务提交，便于 `git revert`。

## `task.py start` 前检查

- [x] prd 决策齐：范围 C、色板推导、分段控件
- [x] design / implement 已写
- [ ] 用户审阅规划并同意开始实现
