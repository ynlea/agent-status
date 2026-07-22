import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart' as dmw;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/desktop/desktop_platform.dart';
import 'data/desktop/island_window_bridge.dart';
import 'data/desktop/tray_controller.dart';
import 'data/desktop/window_controller.dart';
import 'data/prefs/settings_store.dart';
import 'ui/desktop/desktop_host.dart';
import 'ui/desktop/island_window_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isQingyaDesktop) {
    // 子窗：独立灵动岛（屏幕顶部吸顶）
    try {
      final current = await dmw.WindowController.fromCurrentEngine();
      if (current.arguments == kIslandWindowArgument) {
        await IslandWindowHost.bootstrapAndRun(const IslandWindowApp());
        return;
      }
    } catch (e) {
      debugPrint('[main] window definition: $e');
    }
  }

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
