# Implement：主窗瞬切 + 岛内形态稳定

## Checklist

### 1. 主窗几何：去掉插值

- [ ] `window_controller.dart`：`enterIslandMode` 改为单次 `setBounds`（删除 `_lerpBounds` 调用）
- [ ] `showMain` 岛→主：单次设到 `_targetMainRect()`，删除插值
- [ ] 确认无其他调用 `_lerpBounds` 后删除该 helper 与仅为其存在的 `dart:math` 依赖（若不再需要）
- [ ] 保持：记忆主窗 bounds、岛 chrome（frameless/透明/alwaysOnTop/skipTaskbar）、恢复 chrome

### 2. 统一尺寸决策

- [ ] 抽出 `islandTargetMetrics(vm, flags) → { visualW/H, windowW/H }` 或等价，供 controller 与 UI 共用
- [ ] 对齐 strip / hover / announce / list 四档与现有常量（`desktop_platform.dart`）
- [ ] `IslandSurface._visualSize` 与 `_targetWindowSize` 改走同一来源

### 3. 串行 morph 管道

- [ ] `IslandController`：引入 `_morphGen` + 可取消的 delayed shrink
- [ ] `_morphToHover` / `_morphToCard` / `_goStrip` / 播报进出 统一走 `requestForm`（或等价命名）
- [ ] 面积↑：先 `resizeIsland`，再改 phase
- [ ] 面积↓：先改 phase，再在 **UI 动画时长对齐** 后 `resizeIsland`（替换固定 delay 与动画不同步的路径）
- [ ] `_syncWindowShape` 与 morph 管道不双写冲突（同目标则 no-op）

### 4. UI 动画收敛

- [ ] `island_bar.dart`：形态尺寸动画单一路径；减弱 strip↔hover 双层 Switcher 导致的抽动
- [ ] 时长与 controller 收 HWND 使用同一套 `kIsland*Ms` 常量
- [ ] 快速切换时不叠加互相打架的 scale

### 5. 验证

- [ ] 手测 Windows：关窗进岛、托盘开主窗 = 瞬切
- [ ] 手测：悬停/离条、点击列表、通知打断、连点，无抽搐
- [ ] 收条后点击穿透正常（无透明挡板）
- [ ] `dart analyze`（desktop 相关文件）无新增 error

## Validation commands

```bash
# 静态
cd mobile && dart analyze lib/data/desktop lib/ui/desktop

# 运行桌面（本机 Windows 或既有流水线）
# flutter run -d windows
```

## Review gates

- 代码中不存在主窗路径的多步 bounds 插值
- morph 打断有 generation 或等价取消
- 尺寸决策单一来源

## Rollback

```bash
git checkout -- mobile/lib/data/desktop/window_controller.dart \
  mobile/lib/data/desktop/island_controller.dart \
  mobile/lib/ui/desktop/island_bar.dart \
  mobile/lib/data/desktop/desktop_platform.dart
```

## Key files

- `mobile/lib/data/desktop/window_controller.dart`
- `mobile/lib/data/desktop/island_controller.dart`
- `mobile/lib/data/desktop/desktop_platform.dart`
- `mobile/lib/ui/desktop/island_bar.dart`
- （若需要）`mobile/lib/ui/desktop/desktop_host.dart`
