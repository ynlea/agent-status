import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_platform.dart';

/// 主窗：正常 / 隐藏 / 关窗后变形为岛。
enum DesktopWindowMode { normal, hidden, island }

/// Windows 主窗控制（单窗方案）。
class QingyaWindowController with WindowListener {
  QingyaWindowController._();

  static final QingyaWindowController instance = QingyaWindowController._();

  DesktopWindowMode _mode = DesktopWindowMode.normal;
  bool _ready = false;
  bool _exitRequested = false;
  bool _transitioning = false;
  final _modeController = StreamController<DesktopWindowMode>.broadcast();
  final _closeRequested = StreamController<void>.broadcast();

  /// 关窗/进岛前记住的主窗几何，再打开时还原。
  Offset? _savedPosition;
  Size? _savedSize;
  bool _savedMaximized = false;

  DesktopWindowMode get mode => _mode;
  Stream<DesktopWindowMode> get modeStream => _modeController.stream;
  Stream<void> get closeRequested => _closeRequested.stream;
  bool get isReady => _ready;
  bool get isBackground =>
      _mode == DesktopWindowMode.hidden || _mode == DesktopWindowMode.island;

  Future<void> init() async {
    if (!isQingyaDesktop || _ready) return;
    await windowManager.ensureInitialized();
    // 主窗用实色底，避免透明 + 缩放导致偶发全黑
    const bg = Color(0xFFFFF9F5);
    const options = WindowOptions(
      size: Size(kDesktopDefaultWidth, kDesktopDefaultHeight),
      minimumSize: Size(kDesktopMinWidth, kDesktopMinHeight),
      // 不用系统跨虚拟桌面居中，改为落在当前显示器
      center: false,
      backgroundColor: bg,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: '轻芽',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      await windowManager.setBackgroundColor(bg);
      await _setSnappedSize(kDesktopDefaultWidth, kDesktopDefaultHeight);
      // 落在当前光标所在显示器中心，避免跨双屏虚拟桌面居中
      await _centerOnActiveDisplay(
        width: kDesktopDefaultWidth,
        height: kDesktopDefaultHeight,
      );
      await windowManager.show();
      await windowManager.focus();
      await _rememberMainBounds();
    });
    windowManager.addListener(this);
    _ready = true;
  }

  Future<void> _setSnappedSize(double width, double height) async {
    await windowManager.setSize(
      Size(width.roundToDouble(), height.roundToDouble()),
    );
  }

  Future<void> _rememberMainBounds() async {
    // 不要让岛形态的尺寸和最大化状态覆盖主窗记忆。
    if (_mode == DesktopWindowMode.island) return;
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      if (_mode == DesktopWindowMode.island) return;
      if (size.width < kDesktopMinWidth * 0.5 ||
          size.height < kDesktopMinHeight * 0.5) {
        return;
      }
      final maximized = await windowManager.isMaximized();
      if (_mode == DesktopWindowMode.island) return;
      _savedMaximized = maximized;
      _savedSize =
          Size(size.width.roundToDouble(), size.height.roundToDouble());
      _savedPosition = Offset(pos.dx.roundToDouble(), pos.dy.roundToDouble());
    } catch (e) {
      debugPrint('[QingyaWindow] remember bounds: $e');
    }
  }

  /// 从托盘/岛恢复主窗（瞬时切换，无几何动画）。
  Future<void> showMain() async {
    if (!isQingyaDesktop || !_ready) return;
    var wait = 0;
    while (_transitioning && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wait++;
    }
    if (_transitioning) return;
    _transitioning = true;
    try {
      await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
      await _restoreNormalChromeProps();
      final target = await _targetMainRect();
      try {
        await windowManager.setBounds(target);
      } catch (_) {}
      if (_savedMaximized) {
        try {
          await windowManager.maximize();
        } catch (_) {}
      }
      _setMode(DesktopWindowMode.normal);
      await windowManager.setSkipTaskbar(false);
      await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      debugPrint('[QingyaWindow] showMain failed: $e\n$st');
      _setMode(DesktopWindowMode.normal);
      try {
        await _restoreNormalChromeProps();
        await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
        await windowManager.setMinimumSize(
          const Size(kDesktopMinWidth, kDesktopMinHeight),
        );
        await _setSnappedSize(kDesktopDefaultWidth, kDesktopDefaultHeight);
        await _centerOnActiveDisplay(
          width: kDesktopDefaultWidth,
          height: kDesktopDefaultHeight,
        );
        await windowManager.show();
        await windowManager.focus();
      } catch (e2) {
        debugPrint('[QingyaWindow] showMain fallback: $e2');
      }
    } finally {
      _transitioning = false;
    }
  }

  Future<void> hideToBackground({required bool preferIsland}) async {
    if (!isQingyaDesktop || !_ready) return;
    var wait = 0;
    while (_transitioning && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wait++;
    }
    if (_transitioning) return;
    if (_mode == DesktopWindowMode.island) return;
    if (_mode == DesktopWindowMode.normal) {
      await _rememberMainBounds();
    }
    if (preferIsland) {
      await enterIslandMode();
    } else {
      await windowManager.hide();
      _setMode(DesktopWindowMode.hidden);
    }
  }

  Future<void> enterIslandMode({
    double width = kIslandWindowWidth,
    double height = kIslandWindowHeight,
  }) async {
    if (!isQingyaDesktop || !_ready) return;
    var wait = 0;
    while (_transitioning && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      wait++;
    }
    if (_transitioning) return;
    if (_mode == DesktopWindowMode.island) {
      await resizeIsland(width: width, height: height);
      return;
    }
    final previousMode = _mode;
    _transitioning = true;
    try {
      if (_mode == DesktopWindowMode.normal) {
        await _rememberMainBounds();
      }
      final w = width.roundToDouble();
      final h = height.roundToDouble();
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
      } catch (_) {}
      await windowManager.setMinimumSize(const Size(80, 24));
      await windowManager.setMaximumSize(const Size(10000, 10000));
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      final pos = await _islandTopCenterOffset(width: w, height: h);
      final to = Rect.fromLTWH(pos.dx, pos.dy, w, h);
      _setMode(DesktopWindowMode.island);
      await windowManager.setBounds(to);
      await windowManager.show();
    } catch (e, st) {
      debugPrint('[QingyaWindow] enterIslandMode: $e\n$st');
      // 进岛过程中任一步失败，都不能留下透明、置顶或不可调整大小的主窗。
      await _restoreNormalChromePropsBestEffort();
      try {
        await windowManager.hide();
        _setMode(DesktopWindowMode.hidden);
      } catch (_) {}
      if (_mode == DesktopWindowMode.island) {
        // 隐藏也失败时，保留实际可见性对应的模式，供下一次恢复调用。
        _setMode(previousMode);
      }
    } finally {
      _transitioning = false;
    }
  }

  Future<void> resizeIsland({
    required double width,
    required double height,
  }) async {
    if (!isQingyaDesktop || !_ready) return;
    // 进岛过渡中稍等，避免播报 HWND 仍卡在细条高度被压扁
    var wait = 0;
    while (_transitioning && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      wait++;
    }
    if (_mode != DesktopWindowMode.island) return;
    if (_transitioning) return;
    _transitioning = true;
    try {
      if (_mode != DesktopWindowMode.island) return;
      final w = width.roundToDouble();
      final h = height.roundToDouble();
      // 以当前窗水平中心 + 顶边为锚点缩放，避免「重新居中」导致细条左右跳
      // 不用系统 animate：Windows 上容易和 Flutter 动画叠成卡断
      double x;
      double y;
      try {
        final cur = await windowManager.getBounds();
        final centerX = cur.left + cur.width / 2;
        x = (centerX - w / 2).roundToDouble();
        y = cur.top.roundToDouble();
      } catch (_) {
        final pos = await _islandTopCenterOffset(width: w, height: h);
        x = pos.dx;
        y = pos.dy;
      }
      if (_mode != DesktopWindowMode.island) return;
      await windowManager.setBounds(
        Rect.fromLTWH(x, y, w, h),
        animate: false,
      );
    } finally {
      _transitioning = false;
    }
  }

  Future<void> hideCompletely() async {
    if (!isQingyaDesktop || !_ready) return;
    var wait = 0;
    while (_transitioning && wait < 40) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      wait++;
    }
    if (_transitioning || _mode == DesktopWindowMode.normal) return;
    _transitioning = true;
    try {
      if (_mode == DesktopWindowMode.normal) return;
      await windowManager.hide();
      _setMode(DesktopWindowMode.hidden);
    } finally {
      _transitioning = false;
    }
  }

  Future<void> quitApp() async {
    if (!isQingyaDesktop) return;
    _exitRequested = true;
    try {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (e) {
      debugPrint('[QingyaWindow] destroy: $e');
    }
  }

  /// 恢复边框/阴影/最小尺寸，用于从岛/背景返回主窗。
  Future<void> _restoreNormalChromeProps() async {
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
    await windowManager.setMinimumSize(
      const Size(kDesktopMinWidth, kDesktopMinHeight),
    );
    await windowManager.setMaximumSize(const Size(10000, 10000));
  }

  /// 进岛失败时逐项恢复 chrome（窗口外观与行为属性），避免单个 API
  /// 失败导致后续属性完全没有机会回滚。
  Future<void> _restoreNormalChromePropsBestEffort() async {
    Object? firstError;

    Future<void> attempt(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        firstError ??= e;
      }
    }

    await attempt(() => windowManager.setAlwaysOnTop(false));
    await attempt(() => windowManager.setResizable(true));
    await attempt(() => windowManager.setHasShadow(true));
    await attempt(() => windowManager.setSkipTaskbar(false));
    await attempt(
      () => windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
    );
    await attempt(
      () => windowManager.setBackgroundColor(const Color(0xFFFFF9F5)),
    );
    await attempt(
      () => windowManager.setMinimumSize(
        const Size(kDesktopMinWidth, kDesktopMinHeight),
      ),
    );
    await attempt(() => windowManager.setMaximumSize(const Size(10000, 10000)));

    if (firstError != null) {
      debugPrint('[QingyaWindow] chrome rollback partial failure: $firstError');
    }
  }

  Future<Rect> _targetMainRect() async {
    final size =
        _savedSize ?? const Size(kDesktopDefaultWidth, kDesktopDefaultHeight);
    final safeW =
        size.width < kDesktopMinWidth ? kDesktopDefaultWidth : size.width;
    final safeH =
        size.height < kDesktopMinHeight ? kDesktopDefaultHeight : size.height;
    final pos = _savedPosition;
    if (pos != null) {
      return Rect.fromLTWH(
        pos.dx.roundToDouble(),
        pos.dy.roundToDouble(),
        safeW.roundToDouble(),
        safeH.roundToDouble(),
      );
    }
    // 没有历史位置时按当前光标所在显示器居中，避免固定坐标落到错误屏幕。
    final display = await _displayForCursorOrPrimary();
    final visible = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    final x = visible.dx + (visibleSize.width - safeW) / 2;
    final y = visible.dy + (visibleSize.height - safeH) / 2;
    return Rect.fromLTWH(
      x.roundToDouble(),
      y.roundToDouble(),
      safeW.roundToDouble(),
      safeH.roundToDouble(),
    );
  }

  /// 主窗居中到光标所在显示器（找不到则主屏），避免跨双屏对半分。
  Future<void> _centerOnActiveDisplay({
    required double width,
    required double height,
  }) async {
    try {
      final display = await _displayForCursorOrPrimary();
      final visible = display.visiblePosition ?? Offset.zero;
      final visibleSize = display.visibleSize ?? display.size;
      final x = (visible.dx + (visibleSize.width - width) / 2).roundToDouble();
      final y =
          (visible.dy + (visibleSize.height - height) / 2).roundToDouble();
      await windowManager.setPosition(Offset(x, y));
    } catch (e) {
      debugPrint('[QingyaWindow] center on display: $e');
      try {
        await windowManager.center();
      } catch (_) {}
    }
  }

  Future<Display> _displayForCursorOrPrimary({Rect? preferredBounds}) async {
    final primary = await screenRetriever.getPrimaryDisplay();
    try {
      final all = await screenRetriever.getAllDisplays();
      if (preferredBounds != null) {
        final savedDisplay =
            _displayContainingPoint(all, preferredBounds.center);
        if (savedDisplay != null) return savedDisplay;
      }
      final cursor = await screenRetriever.getCursorScreenPoint();
      final cursorDisplay = _displayContainingPoint(all, cursor);
      if (cursorDisplay != null) return cursorDisplay;
    } catch (_) {}
    return primary;
  }

  Display? _displayContainingPoint(List<Display> displays, Offset point) {
    for (final display in displays) {
      final origin = display.visiblePosition ?? Offset.zero;
      // 用完整 size 作命中区，兼容任务栏缩小后的 visibleSize。
      final rect = Rect.fromLTWH(
        origin.dx,
        origin.dy,
        display.size.width,
        display.size.height,
      );
      if (rect.contains(point)) return display;
    }
    return null;
  }

  Future<Offset> _islandTopCenterOffset({
    required double width,
    required double height,
  }) async {
    // Display 坐标已是逻辑像素，勿再除 scale
    // 优先使用保存主窗所在的显示器，主窗边界不可用时才看光标和主屏。
    final display = await _displayForCursorOrPrimary(
      preferredBounds: _savedMainBounds(),
    );
    final visible = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    final x = (visible.dx + (visibleSize.width - width) / 2).roundToDouble();
    final y = visible.dy.roundToDouble();
    return Offset(x, y);
  }

  Rect? _savedMainBounds() {
    final position = _savedPosition;
    final size = _savedSize;
    if (position == null || size == null) return null;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }

  void _setMode(DesktopWindowMode next) {
    if (_mode == next) return;
    _mode = next;
    if (!_modeController.isClosed) {
      _modeController.add(next);
    }
  }

  @override
  void onWindowClose() {
    if (_exitRequested) return;
    if (!_closeRequested.isClosed) {
      _closeRequested.add(null);
    }
  }

  /// 系统/任务栏最小化：立刻还原并走关到托盘/岛同一路径。
  @override
  void onWindowMinimize() {
    if (_exitRequested) return;
    if (_mode != DesktopWindowMode.normal) return;
    unawaited(_redirectMinimizeToBackground());
  }

  Future<void> _redirectMinimizeToBackground() async {
    try {
      // 先退出系统最小化，再变成岛/托盘，避免卡在任务栏最小化态
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
    } catch (_) {}
    if (_exitRequested || _mode != DesktopWindowMode.normal) return;
    if (!_closeRequested.isClosed) {
      _closeRequested.add(null);
    }
  }

  /// 标题栏最小化按钮：与关闭一样收进背景（岛/托盘）。
  void requestHideToBackground() {
    if (_exitRequested) return;
    if (!_closeRequested.isClosed) {
      _closeRequested.add(null);
    }
  }

  @override
  void onWindowMove() {
    if (_mode == DesktopWindowMode.normal && !_transitioning) {
      unawaited(_rememberMainBounds());
    }
  }

  @override
  void onWindowResize() {
    if (_mode == DesktopWindowMode.normal && !_transitioning) {
      unawaited(_rememberMainBounds());
    }
  }

  Future<void> dispose() async {
    if (_ready) {
      windowManager.removeListener(this);
    }
    await _modeController.close();
    await _closeRequested.close();
  }
}
