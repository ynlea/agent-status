import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_platform.dart';
import 'island_models.dart';

const kIslandWindowArgument = 'qingya_island';

/// 主窗侧：创建/同步/销毁独立置顶灵动岛子窗。
class IslandWindowBridge {
  IslandWindowBridge._();
  static final IslandWindowBridge instance = IslandWindowBridge._();

  String? _islandWindowId;
  bool _creating = false;

  Future<void> ensureCreated() async {
    if (!isQingyaDesktop) return;
    if (_islandWindowId != null) return;
    if (_creating) return;
    _creating = true;
    try {
      final all = await WindowController.getAll();
      for (final w in all) {
        if (w.arguments == kIslandWindowArgument) {
          _islandWindowId = w.windowId;
          await w.show();
          return;
        }
      }
      final created = await WindowController.create(
        const WindowConfiguration(
          arguments: kIslandWindowArgument,
          hiddenAtLaunch: true,
        ),
      );
      _islandWindowId = created.windowId;
      await created.show();
      debugPrint('[IslandWindow] created id=$_islandWindowId');
    } catch (e, st) {
      debugPrint('[IslandWindow] create failed: $e\n$st');
    } finally {
      _creating = false;
    }
  }

  Future<void> pushState(IslandViewModel vm) async {
    if (!isQingyaDesktop) return;
    if (!vm.enabled) {
      await hide();
      return;
    }
    await ensureCreated();
    final id = _islandWindowId;
    if (id == null) return;
    try {
      final w = WindowController.fromWindowId(id);
      await w.invokeMethod('island_sync', jsonEncode(vm.toJson()));
    } catch (e) {
      debugPrint('[IslandWindow] pushState: $e');
    }
  }

  Future<void> hide() async {
    final id = _islandWindowId;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).hide();
    } catch (e) {
      debugPrint('[IslandWindow] hide: $e');
    }
  }

  Future<void> destroy() async {
    final id = _islandWindowId;
    _islandWindowId = null;
    if (id == null) return;
    try {
      await WindowController.fromWindowId(id).hide();
    } catch (_) {}
  }

  Future<void> bindMainHandler({
    required Future<void> Function(SessionRef session) onOpenSession,
    required Future<void> Function() onShowMain,
  }) async {
    if (!isQingyaDesktop) return;
    try {
      final me = await WindowController.fromCurrentEngine();
      await me.setWindowMethodHandler((call) async {
        switch (call.method) {
          case 'island_open_session':
            final raw = call.arguments;
            if (raw is String) {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              await onOpenSession(SessionRef.fromJson(map));
            }
            return null;
          case 'island_show_main':
            await onShowMain();
            return null;
          default:
            throw MissingPluginException(call.method);
        }
      });
    } catch (e) {
      debugPrint('[IslandWindow] bindMainHandler: $e');
    }
  }
}

class SessionRef {
  const SessionRef({
    required this.machineId,
    required this.agent,
    required this.sessionId,
  });

  final String machineId;
  final String agent;
  final String sessionId;

  factory SessionRef.fromJson(Map<String, dynamic> json) => SessionRef(
        machineId: '${json['machineId'] ?? ''}',
        agent: '${json['agent'] ?? ''}',
        sessionId: '${json['sessionId'] ?? ''}',
      );

  Map<String, dynamic> toJson() => {
        'machineId': machineId,
        'agent': agent,
        'sessionId': sessionId,
      };
}

/// 子窗侧：固定透明画布 + 吸顶，内部再做动画（避免改 HWND 引发抖动）。
class IslandWindowHost {
  static bool _placed = false;

  static Future<void> bootstrapAndRun(Widget app) async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    final w = islandSnap(kIslandWindowWidth);
    final h = islandSnap(kIslandWindowHeight);

    final options = WindowOptions(
      size: Size(w, h),
      minimumSize: Size(w, h),
      maximumSize: Size(w, h),
      backgroundColor: const Color(0x00000000),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      title: '轻芽灵动岛',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setAsFrameless();
      await windowManager.setHasShadow(false);
      await windowManager.setBackgroundColor(const Color(0x00000000));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setResizable(false);
      await windowManager.setPreventClose(true);
      await ensureFixedCanvas();
      await windowManager.show();
    });

    runApp(app);
  }

  /// 只在启动或显示时摆一次固定画布，phase 变化不再改大小。
  static Future<void> ensureFixedCanvas({bool force = false}) async {
    if (_placed && !force) return;
    final w = islandSnap(kIslandWindowWidth);
    final h = islandSnap(kIslandWindowHeight);
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
      final x = islandSnap(originX + (screenW - w) / 2);
      final y = islandSnap(originY + kIslandTopGap);
      await windowManager.setMinimumSize(Size(w, h));
      await windowManager.setMaximumSize(Size(w, h));
      await windowManager.setSize(Size(w, h));
      await windowManager.setPosition(Offset(x, y));
      _placed = true;
    } catch (e) {
      debugPrint('[IslandWindowHost] place: $e');
      try {
        await windowManager.setSize(Size(w, h));
        await windowManager.setAlignment(Alignment.topCenter);
        _placed = true;
      } catch (_) {}
    }
  }

  static Future<void> showCanvas() async {
    await ensureFixedCanvas();
    await windowManager.show();
  }

  static Future<void> hideCanvas() async {
    await windowManager.hide();
  }
}
