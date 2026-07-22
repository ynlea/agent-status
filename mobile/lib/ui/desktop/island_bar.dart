import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_models.dart';
import '../../data/desktop/window_controller.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

const _islandBg = Color(0xF01C1816);
const _islandFg = Color(0xFFFFF8F3);
const _islandMuted = Color(0xFFB8AAA0);

/// 主窗内顶部灵动岛 Overlay。
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
      top: 0,
      left: 0,
      right: 0,
      child: Align(
        alignment: Alignment.topCenter,
        child: IslandSurface(
          viewModel: vm,
          onOpenSession: onOpenSession,
        ),
      ),
    );
  }
}

/// 岛形态全窗 UI（透明底，只画胶囊/卡片）。
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
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: ColoredBox(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: IslandSurface(
            viewModel: vm,
            fillHost: true,
            onOpenSession: onOpenSession,
          ),
        ),
      ),
    );
  }
}

class IslandSurface extends ConsumerWidget {
  const IslandSurface({
    super.key,
    required this.viewModel,
    required this.onOpenSession,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final void Function(Session session) onOpenSession;
  final bool fillHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(islandControllerProvider.notifier);
    return MouseRegion(
      onEnter: (_) => ctrl.onHoverEnter(),
      onExit: (_) => ctrl.onHoverExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: ctrl.onTap,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _IslandBody(
            viewModel: viewModel,
            fillHost: fillHost,
            onOpenSession: onOpenSession,
            onCollapse: ctrl.collapse,
          ),
        ),
      ),
    );
  }
}

class _IslandBody extends StatelessWidget {
  const _IslandBody({
    required this.viewModel,
    required this.onOpenSession,
    required this.onCollapse,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final void Function(Session session) onOpenSession;
  final VoidCallback onCollapse;
  final bool fillHost;

  Color _stateColor(QingyaPalette c, SessionState? state) {
    return switch (state) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      _ => const Color(0xFF8A7E76),
    };
  }

  String _notifyAsset(SessionState? state) {
    return switch (state) {
      SessionState.confirm => QingyaAssets.notifyConfirm,
      SessionState.working => QingyaAssets.notifyWorking,
      SessionState.done => QingyaAssets.notifyDone,
      _ => QingyaAssets.catBrandAvatarV3,
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final phase = viewModel.phase;
    final accent = _stateColor(c, viewModel.primary?.state);

    if (phase == IslandPhase.strip) {
      return _Strip(accent: accent, fillHost: fillHost);
    }

    if (phase == IslandPhase.hover) {
      return _HoverCapsule(
        viewModel: viewModel,
        accent: accent,
        asset: _notifyAsset(viewModel.primary?.state),
        fillHost: fillHost,
      );
    }

    // card
    return _CardPanel(
      viewModel: viewModel,
      accent: accent,
      asset: _notifyAsset(viewModel.primary?.state),
      fillHost: fillHost,
      onOpenSession: onOpenSession,
      onCollapse: onCollapse,
    );
  }
}

class _Strip extends StatelessWidget {
  const _Strip({required this.accent, this.fillHost = false});

  final Color accent;
  final bool fillHost;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fillHost ? double.infinity : kIslandStripWidth,
      height: kIslandStripHeight,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.95),
            _islandBg,
            accent.withValues(alpha: 0.85),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _HoverCapsule extends StatelessWidget {
  const _HoverCapsule({
    required this.viewModel,
    required this.accent,
    required this.asset,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final Color accent;
  final String asset;
  final bool fillHost;

  @override
  Widget build(BuildContext context) {
    final label = viewModel.hasSessions
        ? (viewModel.badgeCount > 1
            ? '${viewModel.primary?.state.labelZh ?? '状态'} · ${viewModel.badgeCount}'
            : (viewModel.primary?.state.labelZh ?? '状态'))
        : '轻芽在线';

    return Container(
      width: fillHost ? double.infinity : kIslandHoverWidth,
      height: kIslandHoverHeight,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xF028221E),
            Color.lerp(const Color(0xF028221E), accent, 0.18)!,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _DotIcon(asset: asset, accent: accent, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _islandFg,
              ),
            ),
          ),
          if (viewModel.badgeCount > 1)
            _Badge(count: viewModel.badgeCount, accent: accent),
        ],
      ),
    );
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    required this.viewModel,
    required this.accent,
    required this.asset,
    required this.onOpenSession,
    required this.onCollapse,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final Color accent;
  final String asset;
  final void Function(Session session) onOpenSession;
  final VoidCallback onCollapse;
  final bool fillHost;

  @override
  Widget build(BuildContext context) {
    final sessions = viewModel.sessions;
    final height = sessions.isEmpty
        ? kIslandCardHeightEmpty
        : (sessions.length == 1 ? 148.0 : kIslandCardHeightList);

    return Container(
      width: fillHost ? double.infinity : kIslandCardWidth,
      height: height,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xF22A2420),
            Color.lerp(const Color(0xF22A2420), accent, 0.12)!,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            child: Row(
              children: [
                _DotIcon(asset: asset, accent: accent, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sessions.isEmpty ? '轻芽' : viewModel.headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: _islandFg,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sessions.isEmpty ? '暂无活跃会话' : viewModel.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: _islandMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onCollapse,
                  icon: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    color: _islandMuted,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          Expanded(
            child: sessions.isEmpty
                ? const Center(
                    child: Text(
                      '有会话时会在这里速览',
                      style: TextStyle(fontSize: 12, color: _islandMuted),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                    itemCount: sessions.length.clamp(0, 6),
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final s = sessions[i];
                      final color = switch (s.state) {
                        SessionState.confirm =>
                          context.qingya.confirm,
                        SessionState.working =>
                          context.qingya.working,
                        SessionState.done => context.qingya.done,
                        _ => _islandMuted,
                      };
                      return Material(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => onOpenSession(s),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: _islandFg,
                                        ),
                                      ),
                                      Text(
                                        [
                                          s.state.labelZh,
                                          s.agent,
                                          if ((s.machineName ?? '')
                                              .trim()
                                              .isNotEmpty)
                                            s.machineName!.trim(),
                                        ].join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _islandMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: _islandMuted,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DotIcon extends StatelessWidget {
  const _DotIcon({
    required this.asset,
    required this.accent,
    required this.size,
  });

  final String asset;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: Image.asset(
          asset,
          width: size * 0.55,
          height: size * 0.55,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color.lerp(_islandFg, accent, 0.15),
        ),
      ),
    );
  }
}
