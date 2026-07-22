import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_platform.dart';

/// 主窗生命周期：正常 / 完全隐藏 / 缩为灵动岛形态。
enum DesktopWindowMode { normal, hidden, island }

/// Windows 主窗控制：默认尺寸、关窗隐藏、岛形态切换。
///
/// 单窗方案：主窗隐藏时把同一窗口改成置顶无边框胶囊，保证岛在关主窗后仍可见。
class WindowController with WindowListener {
  WindowController._();

  static final WindowController instance = WindowController._();

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
      titleBarStyle: TitleBarStyle.normal,
      title: '轻芽',
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    });
    windowManager.addListener(this);
    _ready = true;
  }

  Future<void> showMain() async {
    if (!isQingyaDesktop || !_ready) return;
    await _restoreNormalChrome();
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
    _setMode(DesktopWindowMode.normal);
  }

  /// 关窗：不退出；有岛内容则进入岛形态，否则完全隐藏。
  Future<void> hideToBackground({required bool preferIsland}) async {
    if (!isQingyaDesktop || !_ready) return;
    if (preferIsland) {
      await enterIslandMode();
    } else {
      await windowManager.hide();
      _setMode(DesktopWindowMode.hidden);
    }
  }

  Future<void> enterIslandMode({
    double width = kIslandCapsuleWidth,
    double height = kIslandCapsuleHeight,
  }) async {
    if (!isQingyaDesktop || !_ready) return;
    await windowManager.setMinimumSize(const Size(200, 40));
    await windowManager.setAsFrameless();
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setResizable(false);
    await windowManager.setSize(Size(width, height));
    await _positionIslandTopCenter(width: width, height: height);
    await windowManager.show();
    try {
      await windowManager.blur();
    } catch (_) {}
    _setMode(DesktopWindowMode.island);
  }

  Future<void> resizeIsland({
    required double width,
    required double height,
  }) async {
    if (!isQingyaDesktop || !_ready || _mode != DesktopWindowMode.island) {
      return;
    }
    await windowManager.setSize(Size(width, height));
    await _positionIslandTopCenter(width: width, height: height);
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
      debugPrint('[WindowController] destroy: $e');
    }
  }

  Future<void> _restoreNormalChrome() async {
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(
      const Size(kDesktopMinWidth, kDesktopMinHeight),
    );
    await windowManager.setSize(
      const Size(kDesktopDefaultWidth, kDesktopDefaultHeight),
    );
    await windowManager.center();
  }

  Future<void> _positionIslandTopCenter({
    required double width,
    required double height,
  }) async {
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      final size = display.size;
      final visible = display.visiblePosition;
      final visibleSize = display.visibleSize ?? size;
      final originX = visible?.dx ?? 0;
      final originY = visible?.dy ?? 0;
      final x = originX + (visibleSize.width - width) / 2;
      final y = originY + 12;
      await windowManager.setPosition(Offset(x, y));
    } catch (e) {
      debugPrint('[WindowController] position island: $e');
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
