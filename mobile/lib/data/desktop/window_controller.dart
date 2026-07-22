import 'dart:async';
import 'dart:math' as math;

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
    try {
      _savedMaximized = await windowManager.isMaximized();
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      // 岛形态下读到的是小岛尺寸，不要覆盖主窗记忆
      if (_mode == DesktopWindowMode.island) return;
      if (size.width < kDesktopMinWidth * 0.5 ||
          size.height < kDesktopMinHeight * 0.5) {
        return;
      }
      _savedSize = Size(size.width.roundToDouble(), size.height.roundToDouble());
      _savedPosition = Offset(pos.dx.roundToDouble(), pos.dy.roundToDouble());
    } catch (e) {
      debugPrint('[QingyaWindow] remember bounds: $e');
    }
  }

  /// 从托盘/岛恢复主窗。
  /// 岛→主窗：先恢复边框与实色，再插值放大到记忆位置，最后切主布局。
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
      final wasIsland = _mode == DesktopWindowMode.island;
      final wasHidden = _mode == DesktopWindowMode.hidden;

      if (wasIsland) {
        Rect? from;
        try {
          from = await windowManager.getBounds();
        } catch (_) {}
        await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
        // 先在小岛尺寸上恢复边框/阴影，再平滑放大
        await _restoreNormalChromeProps();
        final target = _targetMainRect();
        if (from != null) {
          await _lerpBounds(from, target, ms: 320);
        } else {
          await windowManager.setBounds(target);
        }
        if (_savedMaximized) {
          try {
            await windowManager.maximize();
          } catch (_) {}
        }
        await Future<void>.delayed(const Duration(milliseconds: 24));
        _setMode(DesktopWindowMode.normal);
        await Future<void>.delayed(const Duration(milliseconds: 40));
      } else {
        _setMode(DesktopWindowMode.normal);
        if (wasHidden || _savedSize != null) {
          await _restoreNormalChrome(fromIsland: false);
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }

      await windowManager.setSkipTaskbar(false);
      await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
      await windowManager.show();
      await windowManager.focus();

      await Future<void>.delayed(const Duration(milliseconds: 48));
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
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
    _transitioning = true;
    try {
      if (_mode == DesktopWindowMode.normal) {
        await _rememberMainBounds();
      }
      final w = width.roundToDouble();
      final h = height.roundToDouble();
      Rect? from;
      try {
        from = await windowManager.getBounds();
      } catch (_) {}
      await windowManager.setMinimumSize(const Size(80, 24));
      await windowManager.setMaximumSize(const Size(10000, 10000));
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
          from = await windowManager.getBounds();
        }
      } catch (_) {}
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      final pos = await _islandTopCenterOffset(width: w, height: h);
      final to = Rect.fromLTWH(pos.dx, pos.dy, w, h);
      // 先切岛 UI，再缩 HWND，避免主界面被压扁一截的割裂感
      _setMode(DesktopWindowMode.island);
      if (from != null && from.width > w * 1.5) {
        // 从当前大窗顶居中收到小岛；内容已是岛，透明底收缩更自然
        await _lerpBounds(from, to, ms: 260);
      } else {
        await windowManager.setBounds(to);
      }
      await windowManager.show();
    } catch (e, st) {
      debugPrint('[QingyaWindow] enterIslandMode: $e\n$st');
      try {
        await windowManager.hide();
        _setMode(DesktopWindowMode.hidden);
      } catch (_) {}
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
    await windowManager.setBounds(
      Rect.fromLTWH(x, y, w, h),
      animate: false,
    );
  }

  Future<void> hideCompletely() async {
    if (!isQingyaDesktop || !_ready) return;
    await windowManager.hide();
    _setMode(DesktopWindowMode.hidden);
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

  /// 仅恢复边框/阴影/最小尺寸，不改几何（用于插值动画前）。
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

  Rect _targetMainRect() {
    final size = _savedSize ??
        const Size(kDesktopDefaultWidth, kDesktopDefaultHeight);
    final safeW = size.width < kDesktopMinWidth
        ? kDesktopDefaultWidth
        : size.width;
    final safeH = size.height < kDesktopMinHeight
        ? kDesktopDefaultHeight
        : size.height;
    final pos = _savedPosition;
    if (pos != null) {
      return Rect.fromLTWH(
        pos.dx.roundToDouble(),
        pos.dy.roundToDouble(),
        safeW.roundToDouble(),
        safeH.roundToDouble(),
      );
    }
    // 无记忆位置时尽量落在主屏中心（同步路径用近似值，异步居中在 restore 里补）
    return Rect.fromLTWH(
      120,
      80,
      safeW.roundToDouble(),
      safeH.roundToDouble(),
    );
  }

  /// 窗口几何插值：缓入缓出，接近 macOS 缩放手感（纯 window_manager，无第三方库）。
  Future<void> _lerpBounds(Rect from, Rect to, {int ms = 300}) async {
    const steps = 8;
    final stepMs = (ms / steps).round().clamp(16, 36);
    for (var i = 1; i <= steps; i++) {
      // easeInOutCubic
      final p = i / steps;
      final t = p < 0.5
          ? 4 * p * p * p
          : 1 - math.pow(-2 * p + 2, 3) / 2;
      final r = Rect.lerp(from, to, t.toDouble())!;
      await windowManager.setBounds(
        Rect.fromLTWH(
          r.left.roundToDouble(),
          r.top.roundToDouble(),
          r.width.roundToDouble().clamp(80, 10000),
          r.height.roundToDouble().clamp(24, 10000),
        ),
      );
      if (i < steps) {
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
    }
  }

  Future<void> _restoreNormalChrome({required bool fromIsland}) async {
    await _restoreNormalChromeProps();

    final target = _targetMainRect();
    await windowManager.setSize(Size(target.width, target.height));

    final pos = _savedPosition;
    if (pos != null) {
      await windowManager.setPosition(
        Offset(pos.dx.roundToDouble(), pos.dy.roundToDouble()),
      );
    } else {
      await _centerOnActiveDisplay(width: target.width, height: target.height);
    }

    if (_savedMaximized) {
      try {
        await windowManager.maximize();
      } catch (_) {}
    }
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
      final x =
          (visible.dx + (visibleSize.width - width) / 2).roundToDouble();
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

  Future<Display> _displayForCursorOrPrimary() async {
    final primary = await screenRetriever.getPrimaryDisplay();
    try {
      final cursor = await screenRetriever.getCursorScreenPoint();
      final all = await screenRetriever.getAllDisplays();
      for (final d in all) {
        final origin = d.visiblePosition ?? Offset.zero;
        // 用 size 作命中区更稳（与 window_manager calcWindowPosition 一致）
        final rect = Rect.fromLTWH(
          origin.dx,
          origin.dy,
          d.size.width,
          d.size.height,
        );
        if (rect.contains(cursor)) return d;
      }
    } catch (_) {}
    return primary;
  }

  Future<Offset> _islandTopCenterOffset({
    required double width,
    required double height,
  }) async {
    // Display 坐标已是逻辑像素，勿再除 scale
    final display = await screenRetriever.getPrimaryDisplay();
    final visible = display.visiblePosition ?? Offset.zero;
    final visibleSize = display.visibleSize ?? display.size;
    final x = (visible.dx + (visibleSize.width - width) / 2).roundToDouble();
    final y = visible.dy.roundToDouble();
    return Offset(x, y);
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
