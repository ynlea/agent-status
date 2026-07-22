import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/tray_controller.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import 'desktop_title_bar.dart';
import 'island_bar.dart';

/// 单窗方案：自定义标题栏 + 主窗内岛 Overlay；关窗后主窗变形为岛。
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
    _mode = QingyaWindowController.instance.mode;
    _closeSub = QingyaWindowController.instance.closeRequested.listen((_) {
      unawaited(_onClose());
    });
    _modeSub = QingyaWindowController.instance.modeStream.listen((m) {
      if (mounted) setState(() => _mode = m);
    });
    ref.read(islandControllerProvider);
  }

  Future<void> _onClose() async {
    await ref.read(islandControllerProvider.notifier).onMainCloseRequested();
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

    final island = ref.watch(islandControllerProvider);
    final ctrl = ref.read(islandControllerProvider.notifier);

    // 关主窗后的岛形态：只画岛
    if (_mode == DesktopWindowMode.island) {
      return Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: ColoredBox(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: IslandSurface(
              viewModel: island,
              standalone: true,
              onOpenSession: widget.onOpenSession,
              onHoverEnter: ctrl.onHoverEnter,
              onHoverExit: ctrl.onHoverExit,
              onTap: ctrl.onTap,
              onCollapse: ctrl.collapse,
              onAnnouncementFinished: ctrl.onAnnouncementFinished,
            ),
          ),
        ),
      );
    }

    // 正常主窗：标题栏 + 内容 + 顶部岛 Overlay
    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              if (island.isVisible)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: IslandSurface(
                      viewModel: island,
                      onOpenSession: widget.onOpenSession,
                      onHoverEnter: ctrl.onHoverEnter,
                      onHoverExit: ctrl.onHoverExit,
                      onTap: ctrl.onTap,
                      onCollapse: ctrl.collapse,
                      onAnnouncementFinished: ctrl.onAnnouncementFinished,
                    ),
                  ),
                ),
            ],
          ),
        ),
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
