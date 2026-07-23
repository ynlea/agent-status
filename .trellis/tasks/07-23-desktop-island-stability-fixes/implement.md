# 实施计划：桌面灵动岛稳定性修复

## 执行清单

- [x] 阅读桌面 frontend（前端）规范和父任务当前改动，确认不覆盖用户未提交修改。
- [x] 在 `IslandController` 中统一失效 morph、延迟收缩和窗口形状同步请求；补销毁后的异步保护。
- [x] 在 `QingyaWindowController` 中修正显示器选择，并为进岛失败补充 chrome 回滚。
- [x] 增加可自动执行的纯状态回归测试；平台窗口仍由 Windows 实机验证。
- [x] 运行 Dart 静态检查和完整 Flutter 测试。
- [ ] 在 Windows 实机验证副屏、托盘恢复、快速悬停/点击和通知打断。
- [x] 复核日志量、未改变的通知/过滤语义和父任务差异；本次不更新现有 Kotlin Android 规范。

## 当前验证结果

- `dart analyze`：桌面实现与相关测试无问题。
- `flutter test`：12 项全部通过，包含视觉回归测试。
- `git diff --check`：通过。
- Windows 实机：当前环境不可执行，保留为任务完成前的唯一待办。

## 验证命令

```bash
cd mobile
dart analyze lib/data/desktop lib/ui/desktop
flutter test test --reporter expanded
```

Windows 实机：

- 主窗位于副显示器时进入/退出灵动岛。
- 连续悬停、离开、点击列表和通知打断。
- 禁用灵动岛、重新启用、关闭窗口和销毁控制器。

## 评审门槛

- 代码中不存在未版本化的延迟窗口调整。
- 所有关键异步窗口调用返回后都验证当前请求仍然有效。
- 进岛失败后可无条件恢复正常主窗 chrome。
- 新增测试能复现并防止本任务列出的三类竞态。

## 回滚点

只回滚本任务实际修改的桌面控制器和测试文件，不覆盖父任务已有变更。
