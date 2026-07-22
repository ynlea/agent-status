import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/island_controller.dart';
import '../../data/desktop/island_models.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

const _islandFg = Color(0xFFFFF8F3);
const _islandMuted = Color(0xFFB8AAA0);
const _islandDeep = Color(0xF21A1614);

/// 主窗不再内嵌 Overlay。
class DesktopIslandOverlay extends ConsumerWidget {
  const DesktopIslandOverlay({
    super.key,
    required this.onOpenSession,
  });

  final void Function(Session session) onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const SizedBox.shrink();
  }
}

class IslandSurface extends StatefulWidget {
  const IslandSurface({
    super.key,
    required this.viewModel,
    required this.onOpenSession,
    this.onHoverEnter,
    this.onHoverExit,
    this.onTap,
    this.onCollapse,
    this.onAnnouncementFinished,
    this.fillHost = false,
    this.standalone = false,
  });

  final IslandViewModel viewModel;
  final void Function(Session session) onOpenSession;
  final VoidCallback? onHoverEnter;
  final VoidCallback? onHoverExit;
  final VoidCallback? onTap;
  final VoidCallback? onCollapse;
  final VoidCallback? onAnnouncementFinished;
  final bool fillHost;
  final bool standalone;

  @override
  State<IslandSurface> createState() => _IslandSurfaceState();
}

class _IslandSurfaceState extends State<IslandSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _enter;
  late IslandPhase _lastPhase;

  @override
  void initState() {
    super.initState();
    _lastPhase = widget.viewModel.phase;
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    if (widget.standalone) {
      // 关主窗进岛：细条从顶上“落入”并略回弹
      _enter.forward(from: 0);
    } else {
      _enter.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant IslandSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel.phase != widget.viewModel.phase) {
      _lastPhase = oldWidget.viewModel.phase;
    }
    // 从主窗再次变岛时重播入场
    if (widget.standalone &&
        !oldWidget.standalone &&
        widget.viewModel.isVisible) {
      unawaited(_enter.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  bool _isExpanding(IslandPhase from, IslandPhase to) {
    int rank(IslandPhase p) => switch (p) {
          IslandPhase.hidden => 0,
          IslandPhase.strip => 1,
          IslandPhase.hover => 2,
          IslandPhase.card => 3,
        };
    return rank(to) > rank(from);
  }

  Duration _morphDuration(IslandPhase from, IslandPhase to) {
    final expanding = _isExpanding(from, to);
    if (to == IslandPhase.card || from == IslandPhase.card) {
      return Duration(
        milliseconds: expanding ? kIslandCardExpandMs : kIslandCardCollapseMs,
      );
    }
    return Duration(
      milliseconds: expanding ? kIslandExpandMs : kIslandCollapseMs,
    );
  }

  Curve _morphCurve(IslandPhase from, IslandPhase to) {
    if (_isExpanding(from, to)) {
      // 展开：快起缓停（回弹交给内容 Scale，避免尺寸越界裁切）
      return const Cubic(0.16, 1.0, 0.3, 1.0);
    }
    // 收起：顺滑减速
    return Curves.easeInOutCubic;
  }

  (double, double) _visualSize(IslandViewModel vm) {
    return switch (vm.phase) {
      IslandPhase.hidden => (kIslandStripWidth, kIslandStripHeight),
      IslandPhase.strip => (kIslandStripWidth, kIslandStripHeight),
      IslandPhase.hover => (kIslandHoverWidth, kIslandHoverHeight),
      IslandPhase.card => vm.hasAnnouncement
          ? (kIslandAnnounceWidth, kIslandAnnounceHeight)
          : (
              kIslandCardWidth,
              vm.hasSessions
                  ? (vm.sessions.length == 1 ? 150.0 : kIslandCardHeightList)
                  : kIslandCardHeightEmpty,
            ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    if (!viewModel.isVisible) return const SizedBox.shrink();

    final size = _visualSize(viewModel);
    final from = _lastPhase;
    final to = viewModel.phase;
    final duration = _morphDuration(from, to);
    final curve = _morphCurve(from, to);

    return Align(
      alignment: Alignment.topCenter,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_enter.value);
          // 入场：自顶部轻微下移 + 缩放 + 淡入
          final dy = (1 - t) * -10;
          final scale = 0.72 + 0.28 * t;
          return Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => widget.onHoverEnter?.call(),
          onExit: (_) => widget.onHoverExit?.call(),
          child: GestureDetector(
            behavior: HitTestBehavior.deferToChild,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: duration,
              curve: curve,
              width: widget.fillHost ? double.infinity : size.$1,
              height: size.$2,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: Duration(
                  milliseconds: (duration.inMilliseconds * 0.72).round(),
                ),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) {
                  return Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      ...previous,
                      if (current != null) current,
                    ],
                  );
                },
                transitionBuilder: (child, anim) {
                  final fade = CurvedAnimation(
                    parent: anim,
                    curve: Curves.easeOutCubic,
                  );
                  final scale = Tween<double>(begin: 0.92, end: 1).animate(
                    CurvedAnimation(
                      parent: anim,
                      curve: Curves.easeOutBack,
                    ),
                  );
                  return FadeTransition(
                    opacity: fade,
                    child: ScaleTransition(
                      scale: scale,
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(
                    '${viewModel.phase.name}_'
                    '${viewModel.hasAnnouncement}_'
                    '${viewModel.pinned}_'
                    '${viewModel.badgeCount}',
                  ),
                  child: _IslandBody(
                    viewModel: viewModel,
                    fillHost: widget.fillHost,
                    onOpenSession: widget.onOpenSession,
                    onCollapse: widget.onCollapse,
                    onAnnouncementFinished: widget.onAnnouncementFinished,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class IslandSurfaceConnected extends ConsumerWidget {
  const IslandSurfaceConnected({
    super.key,
    required this.onOpenSession,
  });

  final void Function(Session session) onOpenSession;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isQingyaDesktop) return const SizedBox.shrink();
    final vm = ref.watch(islandControllerProvider);
    final ctrl = ref.read(islandControllerProvider.notifier);
    return IslandSurface(
      viewModel: vm,
      onOpenSession: onOpenSession,
      onHoverEnter: ctrl.onHoverEnter,
      onHoverExit: ctrl.onHoverExit,
      onTap: ctrl.onTap,
      onCollapse: ctrl.collapse,
      onAnnouncementFinished: ctrl.onAnnouncementFinished,
    );
  }
}

class _IslandBody extends StatelessWidget {
  const _IslandBody({
    required this.viewModel,
    required this.onOpenSession,
    this.onCollapse,
    this.onAnnouncementFinished,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final void Function(Session session) onOpenSession;
  final VoidCallback? onCollapse;
  final VoidCallback? onAnnouncementFinished;
  final bool fillHost;

  Color _stateColor(QingyaPalette c, SessionState? state) {
    return switch (state) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      _ => const Color(0xFF8A7E76),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final phase = viewModel.phase;
    final accent = _stateColor(
      c,
      viewModel.announcement?.state ?? viewModel.primary?.state,
    );

    if (phase == IslandPhase.strip) {
      return _Strip(accent: accent, fillHost: fillHost);
    }

    if (phase == IslandPhase.hover) {
      return _HoverCapsule(
        viewModel: viewModel,
        accent: accent,
        fillHost: fillHost,
      );
    }

    if (viewModel.hasAnnouncement) {
      return _AnnouncementCard(
        announcement: viewModel.announcement!,
        accent: accent,
        fillHost: fillHost,
        onFinished: onAnnouncementFinished,
      );
    }

    return _CardPanel(
      viewModel: viewModel,
      accent: accent,
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
    // 命中像素 = 细条本身；颜色代表当前最高优先级状态
    return _GlowShell(
      accent: accent,
      intensity: 0.65,
      pulse: true,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: fillHost ? double.infinity : kIslandStripWidth,
        height: kIslandStripHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            colors: [
              Color.lerp(accent, Colors.white, 0.28)!,
              accent,
              Color.lerp(accent, _islandDeep, 0.28)!,
            ],
          ),
        ),
      ),
    );
  }
}

class _HoverCapsule extends StatelessWidget {
  const _HoverCapsule({
    required this.viewModel,
    required this.accent,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final Color accent;
  final bool fillHost;

  @override
  Widget build(BuildContext context) {
    // 与 App 常驻监听通知同文案：x 台在线 · x 个进行中任务 · 172M
    final summary = viewModel.connected
        ? viewModel.liveSummaryLine
        : '轻芽 · 未连接';

    return _GlowShell(
      accent: accent,
      intensity: 0.7,
      pulse: true,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: fillHost ? double.infinity : kIslandHoverWidth,
        height: kIslandHoverHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xF02C2420),
              Color.lerp(const Color(0xF02C2420), accent, 0.22)!,
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            _AppBadge(accent: accent, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                summary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _islandFg,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnouncementCard extends StatefulWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.accent,
    this.fillHost = false,
    this.onFinished,
  });

  final IslandAnnouncement announcement;
  final Color accent;
  final bool fillHost;
  final VoidCallback? onFinished;

  @override
  State<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends State<_AnnouncementCard>
    with TickerProviderStateMixin {
  late final AnimationController _marquee;
  late final AnimationController _sweep;
  final _textKey = GlobalKey();
  double _textWidth = 0;
  double _viewWidth = 0;
  bool _needsMarquee = false;
  bool _finished = false;
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    _marquee = AnimationController(vsync: this);
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndRun());
  }

  @override
  void didUpdateWidget(covariant _AnnouncementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.announcement.line != widget.announcement.line) {
      _finished = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndRun());
    }
  }

  void _measureAndRun() {
    final box = _textKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted) return;
    _textWidth = box?.size.width ?? 0;
    _viewWidth = (widget.fillHost
            ? math.min(MediaQuery.sizeOf(context).width, kIslandAnnounceWidth)
            : kIslandAnnounceWidth) -
        78;
    final overflow = (_textWidth - _viewWidth).clamp(0.0, 4000.0);
    _needsMarquee = overflow > 1;
    setState(() {});

    _finishTimer?.cancel();
    _marquee.stop();
    // 总展示时长固定；溢出才左右滚
    const totalMs = kIslandAnnounceSeconds * 1000;
    _finishTimer = Timer(const Duration(milliseconds: totalMs), () {
      if (_finished || !mounted) return;
      _finished = true;
      widget.onFinished?.call();
    });
    if (_needsMarquee) {
      _marquee.duration = const Duration(milliseconds: totalMs);
      unawaited(_marquee.forward(from: 0));
    }
  }

  @override
  void dispose() {
    _finishTimer?.cancel();
    _marquee.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.announcement;
    final baseA = const Color(0xF02C2420);
    final baseB = Color.lerp(baseA, widget.accent, 0.28)!;

    // 与悬停胶囊同款：矮胶囊 + 从左到右循环脉冲光
    return _GlowShell(
      accent: widget.accent,
      intensity: 0.85,
      pulse: false,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedBuilder(
        animation: _sweep,
        builder: (context, child) {
          final t = _sweep.value;
          // 光带从左扫到右，循环
          final x = -1.2 + t * 2.4;
          return Container(
            width: widget.fillHost ? double.infinity : kIslandAnnounceWidth,
            height: kIslandAnnounceHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: LinearGradient(
                begin: Alignment(x - 0.55, 0),
                end: Alignment(x + 0.55, 0),
                colors: [
                  baseA,
                  baseB,
                  Color.lerp(widget.accent, Colors.white, 0.55)!
                      .withValues(alpha: 0.85),
                  baseB,
                  baseA,
                ],
                stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
              ),
              border: Border.all(color: widget.accent.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: child,
          );
        },
        child: Row(
          children: [
            _AppBadge(accent: widget.accent, size: 26, glowing: true),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${a.state.labelZh} · ${a.machineName} · ${a.agentLabel} · ${a.projectLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: widget.accent,
                      height: 1.15,
                    ),
                  ),
                  ClipRect(
                    child: SizedBox(
                      height: 16,
                      child: AnimatedBuilder(
                        animation: _marquee,
                        builder: (context, child) {
                          if (!_needsMarquee) return child!;
                          final overflow =
                              (_textWidth - _viewWidth).clamp(0.0, 4000.0);
                          return Transform.translate(
                            offset: Offset(-overflow * _marquee.value, 0),
                            child: child,
                          );
                        },
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: 1,
                          child: Text(
                            a.prompt,
                            key: _textKey,
                            maxLines: 1,
                            softWrap: false,
                            overflow: _needsMarquee
                                ? TextOverflow.visible
                                : TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _islandMuted,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardPanel extends StatelessWidget {
  const _CardPanel({
    required this.viewModel,
    required this.accent,
    required this.onOpenSession,
    this.onCollapse,
    this.fillHost = false,
  });

  final IslandViewModel viewModel;
  final Color accent;
  final void Function(Session session) onOpenSession;
  final VoidCallback? onCollapse;
  final bool fillHost;

  @override
  Widget build(BuildContext context) {
    final sessions = viewModel.sessions;
    final height = sessions.isEmpty
        ? kIslandCardHeightEmpty
        : (sessions.length == 1 ? 148.0 : kIslandCardHeightList);

    return _GlowShell(
      accent: accent,
      intensity: 0.5,
      pulse: false,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: fillHost ? double.infinity : kIslandCardWidth,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xF22A2420),
              Color.lerp(const Color(0xF22A2420), accent, 0.14)!,
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.38)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
              child: Row(
                children: [
                  _AppBadge(accent: accent, size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sessions.isEmpty ? '轻芽' : '会话列表',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: _islandFg,
                          ),
                        ),
                        Text(
                          sessions.isEmpty
                              ? (viewModel.connected ? '暂无活跃会话' : '未连接')
                              : '${sessions.length} 个活跃',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: _islandMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onCollapse != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
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
                        '有会话变化时会在这里提醒',
                        style: TextStyle(fontSize: 12, color: _islandMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                      itemCount: sessions.length.clamp(0, 6),
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        final s = sessions[i];
                        final ann = IslandAnnouncement.fromSession(s);
                        final color = switch (s.state) {
                          SessionState.confirm => context.qingya.confirm,
                          SessionState.working => context.qingya.working,
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
                                      boxShadow: [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.55),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          [
                                            ann.state.labelZh,
                                            ann.machineName,
                                            ann.agentLabel,
                                            ann.projectLabel,
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: _islandFg,
                                          ),
                                        ),
                                        Text(
                                          ann.prompt,
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
      ),
    );
  }
}

/// 主题色光晕壳：柔和外发光，可选呼吸脉冲。
class _GlowShell extends StatefulWidget {
  const _GlowShell({
    required this.accent,
    required this.child,
    required this.borderRadius,
    this.intensity = 0.6,
    this.pulse = false,
  });

  final Color accent;
  final Widget child;
  final BorderRadius borderRadius;
  final double intensity;
  final bool pulse;

  @override
  State<_GlowShell> createState() => _GlowShellState();
}

class _GlowShellState extends State<_GlowShell>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.pulse) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _GlowShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && _pulse == null) {
      _pulse = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    } else if (!widget.pulse && _pulse != null) {
      _pulse!.dispose();
      _pulse = null;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget shell(double t) {
      final i = widget.intensity * (0.75 + 0.25 * t);
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: [
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.22 * i),
              blurRadius: 18 + 10 * i,
              spreadRadius: 0.5,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: widget.accent.withValues(alpha: 0.12 * i),
              blurRadius: 28 + 12 * i,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: widget.child,
      );
    }

    final controller = _pulse;
    if (controller == null) return shell(1);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(controller.value);
        return shell(t);
      },
    );
  }
}

class _AppBadge extends StatelessWidget {
  const _AppBadge({
    required this.accent,
    required this.size,
    this.glowing = false,
  });

  final Color accent;
  final double size;
  final bool glowing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: accent.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: glowing ? 0.45 : 0.2),
            blurRadius: glowing ? 12 : 6,
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        QingyaAssets.catAppIcon,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Image.asset(
          QingyaAssets.catBrandAvatarV3,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

