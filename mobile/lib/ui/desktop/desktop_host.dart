import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart' as dmw;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_window_bridge.dart';
import '../../data/desktop/tray_controller.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import 'desktop_title_bar.dart';

/// 挂载在 QingyaApp 上：托盘、关窗、独立灵动岛桥接。
class DesktopHost extends ConsumerStatefulWidget {
  const DesktopHost({
    super.key,
    required this.child,
    required this.onOpenSession,
  });

  final Widget child;
  final void Function(Session session) onOpenSession;

  @override
  ConsumerState<DesktopHost> createState() => _DesktopHostState();
}

class _DesktopHostState extends ConsumerState<DesktopHost> {
  StreamSubscription<void>? _closeSub;

  @override
  void initState() {
    super.initState();
    if (!isQingyaDesktop) return;
    _closeSub = QingyaWindowController.instance.closeRequested.listen((_) {
      unawaited(_onClose());
    });
    // 创建岛控制器 + 子窗
    ref.read(islandControllerProvider);
    unawaited(_bindIslandBridge());
  }

  Future<void> _bindIslandBridge() async {
    await IslandWindowBridge.instance.ensureCreated();
    await IslandWindowBridge.instance.bindMainHandler(
      onOpenSession: (s) async {
        widget.onOpenSession(
          Session(
            machineId: s.machineId,
            agent: s.agent,
            sessionId: s.sessionId,
            displayName: s.sessionId,
            state: SessionState.idle,
            message: '',
          ),
        );
      },
      onShowMain: () async {
        await QingyaWindowController.instance.showMain();
      },
    );

    // 额外接收播报结束
    try {
      final me = await dmw.WindowController.fromCurrentEngine();
      await me.setWindowMethodHandler((call) async {
        switch (call.method) {
          case 'island_open_session':
            final raw = call.arguments;
            if (raw is String) {
              final map = jsonDecode(raw) as Map<String, dynamic>;
              final s = SessionRef.fromJson(map);
              widget.onOpenSession(
                Session(
                  machineId: s.machineId,
                  agent: s.agent,
                  sessionId: s.sessionId,
                  displayName: s.sessionId,
                  state: SessionState.idle,
                  message: '',
                ),
              );
            }
            return null;
          case 'island_show_main':
            await QingyaWindowController.instance.showMain();
            return null;
          case 'island_announcement_done':
            ref.read(islandControllerProvider.notifier).onAnnouncementFinished();
            return null;
          default:
            return null;
        }
      });
    } catch (e) {
      debugPrint('[DesktopHost] bind: $e');
    }

    // 推一次当前状态
    final vm = ref.read(islandControllerProvider);
    await IslandWindowBridge.instance.pushState(vm);
  }

  Future<void> _onClose() async {
    await ref.read(islandControllerProvider.notifier).onMainCloseRequested();
    // 只隐藏主窗，不变形为主岛
    await QingyaWindowController.instance.hideToBackground(preferIsland: false);
  }

  @override
  void dispose() {
    unawaited(_closeSub?.cancel() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isQingyaDesktop) return widget.child;
    // 监听岛状态变化，持续推到子窗
    ref.listen(islandControllerProvider, (_, next) {
      unawaited(IslandWindowBridge.instance.pushState(next));
    });
    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// 启动时初始化主窗与托盘。
Future<void> initDesktopShell({
  required void Function() onShowMain,
  required void Function() onQuit,
}) async {
  if (!isQingyaDesktop) return;
  await QingyaWindowController.instance.init();
  await TrayController.instance.init(
    onShowMain: onShowMain,
    onQuit: onQuit,
  );
}
