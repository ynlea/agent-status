import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/desktop/desktop_platform.dart';
import 'data/desktop/tray_controller.dart';
import 'data/desktop/window_controller.dart';
import 'data/prefs/settings_store.dart';
// 保证 AOT 保留岛窗入口 islandMain（@pragma entry-point）。
import 'island_main.dart' as island_entry;
import 'ui/desktop/desktop_host.dart';

// 防止 tree-shake 误删 island_entry 库（部分工具链对 entry-point 扫描不完整）。
// ignore: unused_element
final _keepIsland = island_entry.islandMain;

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isQingyaDesktop) {
    await initDesktopShell(
      onShowMain: () {
        unawaited(QingyaWindowController.instance.showMain());
      },
      onQuit: () {
        unawaited(TrayController.instance.quit());
      },
    );
  }

  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
      ],
      child: const QingyaApp(),
    ),
  );
}
