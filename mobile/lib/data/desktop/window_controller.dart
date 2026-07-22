import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_platform.dart';

/// 主窗生命周期：正常 / 隐藏（岛由原生窗独立承载）。
enum DesktopWindowMode { normal, hidden }

/// Windows 主窗控制：自定义标题栏、关窗隐藏。
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
  bool get isBackground => _mode == DesktopWindowMode.hidden;

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

  /// 窗口尺寸取整，减轻非整数 DPR 下的二次拉伸发糊。
  Future<void> _setSnappedSize(double width, double height) async {
    final w = width.roundToDouble();
    final h = height.roundToDouble();
    await windowManager.setSize(Size(w, h));
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
    await windowManager.hide();
    _setMode(DesktopWindowMode.hidden);
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
