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
  /// 岛 HWND 面积，用于判断展开是否用系统动画。
  double? _appliedIslandArea;

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
  /// 从岛回来时先还原 HWND 几何与实色底，再切主布局，避免小透明面放大成全黑。
  Future<void> showMain() async {
    if (!isQingyaDesktop || !_ready) return;
    // 切换中不丢请求：等上一轮结束（托盘连点 / 关窗进岛交叉）
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
        // 1) 仍在岛 UI 时先把窗体拉回主窗尺寸 + 实色，避免大布局画进 320×72
        await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
        await _restoreNormalChrome(fromIsland: true);
        await Future<void>.delayed(const Duration(milliseconds: 40));
        // 2) 几何就绪后再切 Flutter 主布局
        _setMode(DesktopWindowMode.normal);
        await Future<void>.delayed(const Duration(milliseconds: 48));
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

      // 再推一帧，防止表面尺寸与布局不同步
      await Future<void>.delayed(const Duration(milliseconds: 64));
      try {
        await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
        await windowManager.show();
        await windowManager.focus();
      } catch (_) {}
    } catch (e, st) {
      debugPrint('[QingyaWindow] showMain failed: $e\n$st');
      // 失败也尽量回到 normal，避免岛永久消失、窗体卡死
      _setMode(DesktopWindowMode.normal);
      try {
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
    // 已在主窗显示流程中或已是岛则不再进岛
    if (_mode == DesktopWindowMode.island) {
      // 仅调整尺寸（卡片档）
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
      await windowManager.setMinimumSize(const Size(80, 24));
      await windowManager.setMaximumSize(const Size(10000, 10000));
      // 若当前最大化，先还原再缩，避免几何错乱
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
      } catch (_) {}
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      final pos = await _islandTopCenterOffset(width: w, height: h);
      // 先到位再 show，避免主窗缩到屏顶时闪一下大块
      await windowManager.setBounds(Rect.fromLTWH(pos.dx, pos.dy, w, h));
      _appliedIslandArea = w * h;
      await windowManager.show();
      _setMode(DesktopWindowMode.island);
    } catch (e, st) {
      debugPrint('[QingyaWindow] enterIslandMode: $e\n$st');
      // 进岛失败则至少隐藏，避免半残窗
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
    if (!isQingyaDesktop || !_ready || _mode != DesktopWindowMode.island) {
      return;
    }
    if (_transitioning) return;
    final w = width.roundToDouble();
    final h = height.roundToDouble();
    // 一次 setBounds；展开时尝试系统动画，收起时瞬时以免拖泥带水
    final pos = await _islandTopCenterOffset(width: w, height: h);
    final growing = (_appliedIslandArea == null) ||
        (w * h > (_appliedIslandArea!));
    await windowManager.setBounds(
      Rect.fromLTWH(pos.dx, pos.dy, w, h),
      animate: growing,
    );
    _appliedIslandArea = w * h;
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

  Future<void> _restoreNormalChrome({required bool fromIsland}) async {
    // 退出无边框：文档说明用 setTitleBarStyle 恢复 frame
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setHasShadow(true);
    await windowManager.setSkipTaskbar(false);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    // 主窗用暖色实底，避免透明表面在尺寸跳变后全黑
    await windowManager.setBackgroundColor(const Color(0xFFFFF9F5));
    await windowManager.setMinimumSize(
      const Size(kDesktopMinWidth, kDesktopMinHeight),
    );
    await windowManager.setMaximumSize(const Size(10000, 10000));

    final size = _savedSize ??
        const Size(kDesktopDefaultWidth, kDesktopDefaultHeight);
    // 防止误存成小岛尺寸
    final safeW = size.width < kDesktopMinWidth
        ? kDesktopDefaultWidth
        : size.width;
    final safeH = size.height < kDesktopMinHeight
        ? kDesktopDefaultHeight
        : size.height;
    await windowManager.setSize(
      Size(safeW.roundToDouble(), safeH.roundToDouble()),
    );

    final pos = _savedPosition;
    if (pos != null) {
      await windowManager.setPosition(
        Offset(pos.dx.roundToDouble(), pos.dy.roundToDouble()),
      );
    } else {
      await _centerOnActiveDisplay(width: safeW, height: safeH);
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
