# Design：主窗瞬切 + 岛内形态稳定动画

## Boundaries

| 模块 | 职责 |
|------|------|
| `QingyaWindowController` | 主窗/岛 HWND 几何与 chrome；**瞬切** enter/leave，岛内 `resizeIsland` 仍瞬时 |
| `IslandController` | phase / pinned / 播报状态机；驱动 HWND 目标尺寸；**串行化**形态 morph |
| `IslandSurface` / `island_bar` | 仅 UI 层形变与内容切换；与 HWND 时序对齐 |
| `desktop_platform.dart` | 视觉尺寸与 HWND pad、动画时长常量 |

## Problem diagnosis（抽搐来源）

1. **主窗路径**：`enterIslandMode` / `showMain` 使用 `_lerpBounds` 多步 `setBounds`，Windows 上每步强制 Flutter relayout → 割裂。
2. **岛内路径竞态**：
   - 展开：`_morphToHover` / `_morphToCard` 先 `resizeIsland` 再改 phase（合理方向，但并发 hover/tap/announce 可重叠）。
   - 收起：`_goStrip(animateHwnd: true)` 用固定 `kIslandHwndShrinkDelayMs` 后再缩 HWND，与真实 `AnimatedContainer` 时长/打断不同步 → 先裁切或后弹一下。
3. **双层动画**：`AnimatedContainer` 尺寸 + `AnimatedSwitcher` 内容淡入，快速切换时 layout 与 opacity 叠帧。
4. **尺寸源不一致**：UI `_visualSize` 与 HWND `_targetWindowSize` 分支条件略有分叉（card 高度、announce vs list），偶发 HWND 与内容差一档。

## Approach

### A. 主窗 ↔ 岛：瞬切

- `enterIslandMode`：记住主窗 bounds → 设岛 chrome → **一次** `setBounds(to)` → `_setMode(island)`（顺序可保持「先 mode 再 bounds」或「先 bounds 再 mode」，但**禁止** `_lerpBounds`）。
- `showMain`：恢复 chrome → **一次** `setBounds(target)`（或 setSize + setPosition）→ `_setMode(normal)` → show/focus。
- 删除或停用 `_lerpBounds` 的调用路径；若无其他引用可删除函数。

### B. 岛内形态：单一「目标态」+ 串行 morph

约定四种**目标形态**（与用户语言对齐）：

| 形态 | 状态条件 | HWND | UI |
|------|----------|------|-----|
| 细条 | strip | strip pad | strip |
| 胶囊 | hover | hover pad | hover capsule |
| 列表 | card 且无 announcement | card pad | list panel |
| 通知 | announcement 播放中 | announce pad | announce card |

**统一 morph 管道**（建议在 `IslandController`）：

```
requestForm(target)
  → 取消未完成的 shrink delay / 上一次 morph Future
  → 若目标 HWND 更大或等大：先 resizeIsland(target)，再 setState(phase/flags)
  → 若目标 HWND 更小：先 setState，再在 UI 动画结束后 resizeIsland(target)
  → 记录 generation token，过期回调忽略
```

- 展开（面积↑）：**先 HWND 放大，再 UI 动画**（避免裁切）。
- 收起（面积↓）：**先 UI 动画，再 HWND 缩小**（用 `duration` 对齐 `kIsland*Ms`，或由 UI 回调 `onMorphComplete`；禁止仅靠与 duration 不一致的魔法 delay）。
- 任何新 `requestForm` 提高 generation，旧 delayed shrink 作废。

### C. UI 层收敛

- 保留单一尺寸动画（`AnimatedContainer` 或 `AnimatedSize`），曲线统一 `easeOutCubic`。
- 细条↔胶囊：弱化或去掉会叠两层布局的 `AnimatedSwitcher` 缩放感；内容可用短 fade 或直接切。
- 列表/通知：内容切换不要第二套会改父尺寸的动画。
- `_visualSize` 与 `_targetWindowSize` **共用同一决策函数**（controller 导出或共享 pure 函数），避免分叉。

### D. 明确不做

- 不恢复双窗岛。
- 不使用 `setBounds(animate: true)` 作为 Windows 方案。
- 不把主窗内容做成缩放 morph。

## Data flow

```
用户/会话事件
  → IslandController 计算目标形态
  → requestForm
      ├─ resizeIsland（按 expand/collapse 时序）
      └─ state = phase/announcement/pinned
  → IslandSurface watch state
      └─ AnimatedContainer 跟视觉尺寸
主窗关闭
  → hideToBackground → enterIslandMode（瞬切）
托盘打开
  → showMain（瞬切）→ mode normal → 岛 UI 不画
```

## Compatibility / rollback

- 仅桌面壳；失败时回退为：瞬切主窗 + 原 island 逻辑（可 git revert 本任务 diff）。
- 无协议/服务端变更。

## Risks

| 风险 | 缓解 |
|------|------|
| 瞬切主窗闪一下 | 先 setBounds/chrome 再 show；岛→主先实色底 |
| 收 HWND 过早裁切 | collapse 必须等 UI duration 或 complete 回调 |
| 快速 hover 抖动 | generation 取消 + hover exit debounce 保留/略调 |
| announce 与 list 尺寸混用 | 单一 size 决策表 |
