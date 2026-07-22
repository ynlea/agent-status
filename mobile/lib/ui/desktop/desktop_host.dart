import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/tray_controller.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import 'island_bar.dart';

/// 挂载在 QingyaApp 上：托盘、关窗、灵动岛。
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
  StreamSubscription<DesktopWindowMode>? _modeSub;
  DesktopWindowMode _mode = DesktopWindowMode.normal;

  @override
  void initState() {
    super.initState();
    if (!isQingyaDesktop) return;
    _mode = WindowController.instance.mode;
    _closeSub = WindowController.instance.closeRequested.listen((_) {
      unawaited(
        ref.read(islandControllerProvider.notifier).onMainCloseRequested(),
      );
    });
    _modeSub = WindowController.instance.modeStream.listen((m) {
      if (mounted) setState(() => _mode = m);
    });
    // 确保 island controller 已创建
    ref.read(islandControllerProvider);
  }

  @override
  void dispose() {
    unawaited(_closeSub?.cancel() ?? Future.value());
    unawaited(_modeSub?.cancel() ?? Future.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isQingyaDesktop) return widget.child;

    // 岛形态时仍 Offstage 保留路由树，避免关窗后导航状态丢失。
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: _mode == DesktopWindowMode.island,
          child: widget.child,
        ),
        if (_mode == DesktopWindowMode.island)
          IslandStandalonePage(onOpenSession: widget.onOpenSession),
        if (_mode == DesktopWindowMode.normal)
          DesktopIslandOverlay(onOpenSession: widget.onOpenSession),
      ],
    );
  }
}

/// 启动时初始化窗口与托盘（main 中调用）。
Future<void> initDesktopShell({
  required void Function() onShowMain,
  required void Function() onQuit,
}) async {
  if (!isQingyaDesktop) return;
  await WindowController.instance.init();
  await TrayController.instance.init(
    onShowMain: onShowMain,
    onQuit: onQuit,
  );
}
