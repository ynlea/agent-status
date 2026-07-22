import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/tray_controller.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import 'desktop_title_bar.dart';
import 'island_bar.dart';

/// 主窗打开：只有标题栏 + 内容，不画灵动岛。
/// 主窗隐藏：整窗变形为屏顶岛。
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

    // 仅主窗隐藏（岛形态）时在屏幕上显示灵动岛
    if (_mode == DesktopWindowMode.island) {
      // 不用全透明 MaterialType，减少缩回主窗时表面残留全黑
      return Material(
        color: const Color(0x00000000),
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
      );
    }

    // 主窗打开：不展示灵动岛
    return ColoredBox(
      color: context.qingya.scaffold,
      child: Column(
        children: [
          const DesktopTitleBar(),
          Expanded(child: widget.child),
        ],
      ),
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
