import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_models.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

/// 暖黑灵动岛底色（贴近品牌，而不是冷灰工具条）。
const _islandBg = Color(0xFF2C2622);
const _islandFg = Color(0xFFFFF8F3);
const _islandMuted = Color(0xFFC9BDB4);

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
      top: 12,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: false,
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
    return Material(
      color: Colors.transparent,
      child: ColoredBox(
        color: Colors.transparent,
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: width,
      height: expanded ? kIslandExpandedHeight : kIslandCapsuleHeight,
      child: Material(
        color: Colors.transparent,
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTapCapsule,
          onDoubleTap: onOpenPrimary,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: accent.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.28),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _islandBg,
                  Color.lerp(_islandBg, accent, 0.14)!,
                ],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 16 : 12,
                vertical: expanded ? 12 : 8,
              ),
              child: Row(
                children: [
                  Container(
                    width: expanded ? 34 : 28,
                    height: expanded ? 34 : 28,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.55),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Image.asset(
                      _notifyAsset(state),
                      width: expanded ? 18 : 15,
                      height: expanded ? 18 : 15,
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
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: _islandFg,
                                  height: 1.15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                viewModel.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: _islandMuted,
                                  height: 1.15,
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
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _islandFg,
                            ),
                          ),
                  ),
                  if (viewModel.badgeCount > 1) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${viewModel.badgeCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color.lerp(_islandFg, accent, 0.2),
                        ),
                      ),
                    ),
                  ],
                  if (expanded) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.north_east_rounded,
                      size: 16,
                      color: _islandMuted.withValues(alpha: 0.9),
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
