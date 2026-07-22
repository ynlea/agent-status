import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/desktop/desktop_platform.dart';
import 'data/desktop/tray_controller.dart';
import 'data/desktop/window_controller.dart';
import 'data/prefs/settings_store.dart';
import 'ui/desktop/desktop_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isQingyaDesktop) {
    await initDesktopShell(
      onShowMain: () {
        unawaited(WindowController.instance.showMain());
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
