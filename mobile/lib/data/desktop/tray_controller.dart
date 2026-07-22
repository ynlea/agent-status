import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';

import 'desktop_platform.dart';
import 'window_controller.dart';

/// 系统托盘：显示主窗口 / 退出。
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
      final iconPath = await _resolveTrayIcon();
      await trayManager.setIcon(iconPath);
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

  Future<String> _resolveTrayIcon() async {
    // Prefer packaged ICO next to runner; fallback extract PNG from assets.
    final exeDir = File(Platform.resolvedExecutable).parent;
    final icoCandidates = [
      '${exeDir.path}/data/flutter_assets/assets/images/cat/cat_app_icon.png',
      '${exeDir.path}/app_icon.ico',
    ];
    for (final p in icoCandidates) {
      if (await File(p).exists()) return p;
    }

    final data = await rootBundle.load('assets/images/cat/cat_app_icon.png');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/qingya_tray_icon.png');
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
    await WindowController.instance.quitApp();
    // 确保进程退出（destroy 后部分环境可能仍驻留）
    exit(0);
  }
}
