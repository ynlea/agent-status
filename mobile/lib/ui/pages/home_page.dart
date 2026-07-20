import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';
import '../widgets/empty_state.dart';
import '../widgets/prototype_widgets.dart';
import '../widgets/task_card.dart';

enum _HomeFilter { all, confirm, working, done }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  _HomeFilter _filter = _HomeFilter.all;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(statusRepositoryProvider);
    final active = snapshot.activeSessions;
    final visible = active.where((session) {
      return switch (_filter) {
        _HomeFilter.all => true,
        _HomeFilter.confirm => session.state == SessionState.confirm,
        _HomeFilter.working => session.state == SessionState.working,
        _HomeFilter.done => session.state == SessionState.done,
      };
    }).toList();

    return Scaffold(
      backgroundColor: QingyaColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: QingyaColors.primary,
          onRefresh: () =>
              ref.read(statusRepositoryProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: QingyaBrandHeader(
                  trailing: ConnectionPill(connected: snapshot.connected),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _HeroCard(activeCount: active.length),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      '活跃任务（${active.length}）',
                      style: const TextStyle(
                        fontSize: 17,
                        color: QingyaColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (snapshot.loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterButton(
                      label: '全部',
                      selected: _filter == _HomeFilter.all,
                      onTap: () => setState(() => _filter = _HomeFilter.all),
                    ),
                    _FilterButton(
                      label: '需确认',
                      selected: _filter == _HomeFilter.confirm,
                      onTap: () =>
                          setState(() => _filter = _HomeFilter.confirm),
                    ),
                    _FilterButton(
                      label: '工作中',
                      selected: _filter == _HomeFilter.working,
                      onTap: () =>
                          setState(() => _filter = _HomeFilter.working),
                    ),
                    _FilterButton(
                      label: '已完成',
                      selected: _filter == _HomeFilter.done,
                      onTap: () => setState(() => _filter = _HomeFilter.done),
                    ),
                  ],
                ),
              ),
              if (snapshot.error != null) ...[
                const SizedBox(height: 10),
                Text(
                  snapshot.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11, color: QingyaColors.confirm),
                ),
              ],
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const SizedBox(
                  height: 320,
                  child: EmptyState(
                    asset: QingyaAssets.catEmptySleepV3,
                    title: '当前没有活跃任务',
                    subtitle: '当有新的任务时，会及时通知你哦～',
                  ),
                )
              else
                ...visible.map(
                  (session) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TaskCard(
                      session: session,
                      onTap: () =>
                          context.push('/devices/${session.machineId}'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 184,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned(
            left: 11,
            top: 27,
            child: _Sparkle(color: Color(0xFFFFD0BE), size: 7),
          ),
          const Positioned(
            left: 150,
            top: 22,
            child: _Sparkle(color: Color(0xFFFFE3D8), size: 5),
          ),
          const Positioned(
            right: 5,
            bottom: 28,
            child: _Sparkle(color: Color(0xFFFFA99C), size: 6),
          ),
          Positioned(
            left: 4,
            top: 67,
            child: _SpeechBubble(
              text: activeCount == 0
                  ? '今天可以休息一下～'
                  : '有 $activeCount 个活跃任务\n在等你哦～',
            ),
          ),
          Positioned(
            right: -8,
            bottom: -4,
            child: Image.asset(
              activeCount == 0
                  ? QingyaAssets.catEmptySleepV3
                  : QingyaAssets.catHeroWinkV3,
              width: activeCount == 0 ? 202 : 218,
              height: 186,
              fit: BoxFit.contain,
              alignment: Alignment.bottomCenter,
            ),
          ),
        ],
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  const _SpeechBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _SpeechBubblePainter(),
      child: SizedBox(
        width: 151,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 22, 12),
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style.copyWith(
                fontSize: 12,
                height: 1.55,
                color: QingyaColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(text: text),
                TextSpan(
                  text: '  ♥',
                  style: TextStyle(
                    color: QingyaColors.primary,
                    fontSize: 11,
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeechBubblePainter extends CustomPainter {
  const _SpeechBubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width - 14, size.height),
          const Radius.circular(15),
        ),
      )
      ..moveTo(size.width - 15, size.height * 0.44)
      ..lineTo(size.width, size.height * 0.56)
      ..lineTo(size.width - 15, size.height * 0.68)
      ..close();
    canvas.drawShadow(path, QingyaColors.shadow, 6, false);
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? QingyaColors.deviceSoft : QingyaColors.idleSoft,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color:
                  selected ? QingyaColors.device : QingyaColors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
