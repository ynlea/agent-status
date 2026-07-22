import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_models.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

/// 正常主窗模式下的顶栏灵动岛（Overlay）。
class DesktopIslandOverlay extends ConsumerWidget {
  const DesktopIslandOverlay({
    super.key,
    required this.onOpenSession,
  });

  final void Function(Session session) onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isQingyaDesktop) return const SizedBox.shrink();
    final mode = WindowController.instance.mode;
    if (mode != DesktopWindowMode.normal) return const SizedBox.shrink();

    final vm = ref.watch(islandControllerProvider);
    if (!vm.isVisible) return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Center(
        child: IslandCapsule(
          viewModel: vm,
          onTapCapsule: () {
            if (vm.phase == IslandPhase.capsule) {
              ref.read(islandControllerProvider.notifier).expand();
            } else if (vm.primary != null) {
              onOpenSession(vm.primary!);
            }
          },
          onOpenPrimary: vm.primary == null
              ? null
              : () => onOpenSession(vm.primary!),
        ),
      ),
    );
  }
}

/// 岛形态全窗 UI（关主窗后窗口本身就是岛）。
class IslandStandalonePage extends ConsumerWidget {
  const IslandStandalonePage({
    super.key,
    required this.onOpenSession,
  });

  final void Function(Session session) onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.watch(islandControllerProvider);
    final c = context.qingya;
    return Material(
      color: Colors.transparent,
      child: ColoredBox(
        color: c.scaffold.withValues(alpha: 0.01),
        child: Center(
          child: IslandCapsule(
            viewModel: vm,
            fillWidth: true,
            onTapCapsule: () {
              if (vm.phase == IslandPhase.capsule) {
                ref.read(islandControllerProvider.notifier).expand();
              } else if (vm.primary != null) {
                onOpenSession(vm.primary!);
              }
            },
            onOpenPrimary: vm.primary == null
                ? null
                : () => onOpenSession(vm.primary!),
          ),
        ),
      ),
    );
  }
}

class IslandCapsule extends StatelessWidget {
  const IslandCapsule({
    super.key,
    required this.viewModel,
    required this.onTapCapsule,
    this.onOpenPrimary,
    this.fillWidth = false,
  });

  final IslandViewModel viewModel;
  final VoidCallback onTapCapsule;
  final VoidCallback? onOpenPrimary;
  final bool fillWidth;

  Color _stateColor(QingyaPalette c, SessionState? state) {
    return switch (state) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      _ => c.idle,
    };
  }

  String _notifyAsset(SessionState? state) {
    return switch (state) {
      SessionState.confirm => QingyaAssets.notifyConfirm,
      SessionState.working => QingyaAssets.notifyWorking,
      SessionState.done => QingyaAssets.notifyDone,
      _ => QingyaAssets.notifyWorking,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final expanded = viewModel.phase == IslandPhase.expanded;
    final state = viewModel.primary?.state;
    final accent = _stateColor(c, state);
    final width = fillWidth
        ? double.infinity
        : (expanded ? kIslandExpandedWidth : kIslandCapsuleWidth);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      height: expanded ? kIslandExpandedHeight : kIslandCapsuleHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTapCapsule,
          onDoubleTap: onOpenPrimary,
          child: Ink(
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.border.withValues(alpha: 0.9)),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: expanded ? 12 : 8,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      _notifyAsset(state),
                      width: 16,
                      height: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: expanded
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                viewModel.headline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: c.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                viewModel.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            viewModel.badgeCount > 1
                                ? '${state?.labelZh ?? '状态'} · ${viewModel.badgeCount}'
                                : (viewModel.primary?.state.labelZh ?? '状态'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: c.textPrimary,
                            ),
                          ),
                  ),
                  if (viewModel.badgeCount > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${viewModel.badgeCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
