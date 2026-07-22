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
  final _modeController = StreamController<DesktopWindowMode>.broadcast();
  final _closeRequested = StreamController<void>.broadcast();

  DesktopWindowMode get mode => _mode;
  Stream<DesktopWindowMode> get modeStream => _modeController.stream;
  Stream<void> get closeRequested => _closeRequested.stream;
  bool get isReady => _ready;
  bool get isBackground =>
      _mode == DesktopWindowMode.hidden || _mode == DesktopWindowMode.island;

  Future<void> init() async {
    if (!isQingyaDesktop || _ready) return;
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      size: Size(kDesktopDefaultWidth, kDesktopDefaultHeight),
      minimumSize: Size(kDesktopMinWidth, kDesktopMinHeight),
      center: true,
      backgroundColor: Color(0x00000000),
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
      await _setSnappedSize(kDesktopDefaultWidth, kDesktopDefaultHeight);
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    _ready = true;
  }

  Future<void> _setSnappedSize(double width, double height) async {
    await windowManager.setSize(
      Size(width.roundToDouble(), height.roundToDouble()),
    );
  }

  Future<void> showMain() async {
    if (!isQingyaDesktop || !_ready) return;
    await _restoreNormalChrome();
    await windowManager.setSkipTaskbar(false);
    await windowManager.setBackgroundColor(const Color(0x00000000));
    await windowManager.show();
    await windowManager.focus();
    _setMode(DesktopWindowMode.normal);
  }

  Future<void> hideToBackground({required bool preferIsland}) async {
    if (!isQingyaDesktop || !_ready) return;
    if (preferIsland) {
      await enterIslandMode();
    } else {
      await windowManager.hide();
      _setMode(DesktopWindowMode.hidden);
    }
  }

  /// 关主窗：整窗变成屏顶小条（内部再画岛 UI）。
  Future<void> enterIslandMode({
    double width = kIslandHoverWidth,
    double height = kIslandHoverHeight + 16,
  }) async {
    if (!isQingyaDesktop || !_ready) return;
    final w = width.roundToDouble().clamp(120.0, 420.0);
    final h = height.roundToDouble().clamp(40.0, 120.0);
    await windowManager.setMinimumSize(Size(w, h));
    await windowManager.setMaximumSize(Size(w, h));
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setBackgroundColor(const Color(0x00000000));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setResizable(false);
    await windowManager.setSize(Size(w, h));
    await _positionIslandTopCenter(width: w, height: h);
    await windowManager.show();
    _setMode(DesktopWindowMode.island);
  }

  Future<void> resizeIsland({
    required double width,
    required double height,
  }) async {
    if (!isQingyaDesktop || !_ready || _mode != DesktopWindowMode.island) {
      return;
    }
    final w = width.roundToDouble().clamp(120.0, 420.0);
    final h = height.roundToDouble().clamp(40.0, 320.0);
    await windowManager.setMinimumSize(Size(w, h));
    await windowManager.setMaximumSize(Size(w, h));
    await windowManager.setSize(Size(w, h));
    await _positionIslandTopCenter(width: w, height: h);
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

  Future<void> _restoreNormalChrome() async {
    await windowManager.setMinimumSize(
      const Size(kDesktopMinWidth, kDesktopMinHeight),
    );
    await windowManager.setMaximumSize(const Size(10000, 10000));
    await windowManager.setHasShadow(true);
    await windowManager.setBackgroundColor(const Color(0x00000000));
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setSkipTaskbar(false);
    await _setSnappedSize(kDesktopDefaultWidth, kDesktopDefaultHeight);
    await windowManager.center();
  }

  Future<void> _positionIslandTopCenter({
    required double width,
    required double height,
  }) async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final rawScale = display.scaleFactor;
      final scale =
          (rawScale == null || rawScale <= 0) ? 1.0 : rawScale.toDouble();
      final visible = display.visiblePosition;
      final visibleSize = display.visibleSize ?? display.size;
      final originX = (visible?.dx ?? 0) / scale;
      final originY = (visible?.dy ?? 0) / scale;
      final screenW = visibleSize.width / scale;
      final x = (originX + (screenW - width) / 2).roundToDouble();
      final y = originY.roundToDouble();
      await windowManager.setPosition(Offset(x, y));
    } catch (e) {
      debugPrint('[QingyaWindow] position island: $e');
      try {
        await windowManager.setAlignment(Alignment.topCenter);
      } catch (_) {}
    }
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

  Future<void> dispose() async {
    if (_ready) {
      windowManager.removeListener(this);
    }
    await _modeController.close();
    await _closeRequested.close();
  }
}
