import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_native_bridge.dart';
import '../../data/desktop/tray_controller.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import 'desktop_title_bar.dart';

/// 托盘、关窗、自定义标题栏；灵动岛走原生置顶分层窗。
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
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    if (!isQingyaDesktop) return;

    _closeSub = QingyaWindowController.instance.closeRequested.listen((_) {
      unawaited(_onClose());
    });

    // 启动岛控制器（会 ensure 原生岛窗）
    ref.read(islandControllerProvider);

    final bridge = IslandNativeBridge.instance;
    unawaited(bridge.bind());
    _subs.add(bridge.openSession$.listen((m) {
      widget.onOpenSession(
        Session(
          machineId: m['machineId'] ?? '',
          agent: m['agent'] ?? '',
          sessionId: m['sessionId'] ?? '',
          displayName: m['sessionId'] ?? '',
          state: SessionState.idle,
          message: '',
        ),
      );
    }));
    _subs.add(bridge.showMain$.listen((_) {
      unawaited(QingyaWindowController.instance.showMain());
    }));
    _subs.add(bridge.announcementDone$.listen((_) {
      ref.read(islandControllerProvider.notifier).onAnnouncementFinished();
    }));
  }

  Future<void> _onClose() async {
    await ref.read(islandControllerProvider.notifier).onMainCloseRequested();
    // 只隐藏主窗；岛窗独立
    await QingyaWindowController.instance.hideToBackground(preferIsland: false);
  }

  @override
  void dispose() {
    unawaited(_closeSub?.cancel() ?? Future.value());
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isQingyaDesktop) return widget.child;

    // 持续把状态推到原生岛窗
    ref.listen(islandControllerProvider, (_, next) {
      unawaited(IslandNativeBridge.instance.sync(next));
    });

    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(child: widget.child),
      ],
    );
  }
}

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
