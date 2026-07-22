import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart' as dmw;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_platform.dart';
import 'island_window_bridge.dart';
import 'window_controller.dart';

/// 系统托盘：显示主窗口 / 退出。Windows 必须使用 .ico。
class TrayController with TrayListener {
  TrayController._();

  static final TrayController instance = TrayController._();

  bool _ready = false;
  VoidCallback? onShowMain;
  VoidCallback? onQuit;

  Future<void> init({
    required VoidCallback onShowMain,
    required VoidCallback onQuit,
  }) async {
    if (!isQingyaDesktop || _ready) return;
    this.onShowMain = onShowMain;
    this.onQuit = onQuit;
    try {
      final iconPath = await _resolveIco();
      debugPrint('[TrayController] icon=$iconPath');
      await trayManager.setIcon(iconPath);
      try {
        await windowManager.setIcon(iconPath);
      } catch (e) {
        debugPrint('[TrayController] window setIcon: $e');
      }
      await trayManager.setToolTip('轻芽');
      await trayManager.setContextMenu(
        Menu(
          items: [
            MenuItem(key: 'show', label: '显示轻芽'),
            MenuItem.separator(),
            MenuItem(key: 'quit', label: '退出'),
          ],
        ),
      );
      trayManager.addListener(this);
      _ready = true;
    } catch (e, st) {
      debugPrint('[TrayController] init failed: $e\n$st');
    }
  }

  Future<String> _resolveIco() async {
    final exeDir = File(Platform.resolvedExecutable).parent;
    final sep = Platform.pathSeparator;
    final candidates = <String>[
      '${exeDir.path}${sep}data${sep}flutter_assets${sep}assets${sep}icons${sep}app_icon.ico',
      '${exeDir.path}${sep}app_icon.ico',
      '${Directory.current.path}${sep}windows${sep}runner${sep}resources${sep}app_icon.ico',
      '${Directory.current.path}${sep}assets${sep}icons${sep}app_icon.ico',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }

    final data = await rootBundle.load('assets/icons/app_icon.ico');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${sep}qingya_tray.ico');
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  @override
  void onTrayIconMouseDown() {
    onShowMain?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        onShowMain?.call();
      case 'quit':
        onQuit?.call();
    }
  }

  Future<void> dispose() async {
    if (!_ready) return;
    trayManager.removeListener(this);
    try {
      await trayManager.destroy();
    } catch (_) {}
    _ready = false;
  }

  Future<void> quit() async {
    await dispose();
    try {
      await IslandWindowBridge.instance.destroy();
      final all = await dmw.WindowController.getAll();
      for (final w in all) {
        if (w.arguments == kIslandWindowArgument) {
          await w.hide();
        }
      }
    } catch (_) {}
    await QingyaWindowController.instance.quitApp();
    exit(0);
  }
}
