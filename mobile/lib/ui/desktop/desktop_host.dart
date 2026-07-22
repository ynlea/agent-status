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
import 'island_bar.dart';

/// 托盘、关窗、自定义标题栏；优先原生岛窗，失败则主窗内 Overlay 兜底。
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
  bool _nativeIslandOk = false;
  bool _nativeChecked = false;

  @override
  void initState() {
    super.initState();
    if (!isQingyaDesktop) return;

    _closeSub = QingyaWindowController.instance.closeRequested.listen((_) {
      unawaited(_onClose());
    });

    ref.read(islandControllerProvider);

    final bridge = IslandNativeBridge.instance;
    unawaited(bridge.bind());
    unawaited(_probeNative());

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

  Future<void> _probeNative() async {
    final ok = await IslandNativeBridge.instance.ensure();
    if (!mounted) return;
    setState(() {
      _nativeIslandOk = ok;
      _nativeChecked = true;
    });
    if (ok) {
      final vm = ref.read(islandControllerProvider);
      await IslandNativeBridge.instance.sync(vm);
    }
  }

  Future<void> _onClose() async {
    await ref.read(islandControllerProvider.notifier).onMainCloseRequested();
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

    final island = ref.watch(islandControllerProvider);
    final ctrl = ref.read(islandControllerProvider.notifier);

    ref.listen(islandControllerProvider, (_, next) {
      if (_nativeIslandOk) {
        unawaited(IslandNativeBridge.instance.sync(next));
      }
    });

    final useOverlayFallback =
        island.isVisible && (_nativeChecked && !_nativeIslandOk);

    return Column(
      children: [
        const DesktopTitleBar(),
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              // 原生岛失败时：主窗顶部 Overlay，至少看得见、不挡全屏
              if (useOverlayFallback)
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
