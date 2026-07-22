import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/repo/status_repository.dart';
import '../../data/repo/usage_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../desktop/desktop_refresh_button.dart';
import '../widgets/assets.dart';
import '../widgets/empty_state.dart';

class UsagePage extends ConsumerStatefulWidget {
  const UsagePage({super.key});

  @override
  ConsumerState<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends ConsumerState<UsagePage> {
  final Set<String> _expanded = {};

  Future<void> _apply(UsageQueryState next) async {
    await ref.read(usageRepositoryProvider.notifier).setQuery(next);
  }

  String _fmtInt(int n) {
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    if (n >= 1000) {
      final s = n.toString();
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }
    return '$n';
  }

  String _fmtRate(double? r) =>
      r == null ? '—' : '${(r * 100).toStringAsFixed(1)}%';

  String _fmtCost(double? c, bool priced) {
    if (c == null) return priced ? '\$0' : '未定价';
    if (c < 0.01) return '\$${c.toStringAsFixed(4)}';
    return '\$${c.toStringAsFixed(2)}';
  }

  String _presetLabel(UsageRangePreset p) => switch (p) {
        UsageRangePreset.today => '今天',
        UsageRangePreset.day1 => '近一天',
        UsageRangePreset.day7 => '近7天',
        UsageRangePreset.day30 => '近30天',
        UsageRangePreset.all => '全部',
        UsageRangePreset.custom => '自定义',
      };

  Future<void> _pickCustom(UsageQueryState q) async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: q.customFrom ?? now.subtract(const Duration(days: 7)),
      firstDate: DateTime(2024),
      lastDate: now,
      helpText: '开始日期',
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: q.customTo ?? now,
      firstDate: from,
      lastDate: now,
      helpText: '结束日期',
    );
    if (to == null || !mounted) return;
    await _apply(q.copyWith(
      preset: UsageRangePreset.custom,
      customFrom: DateTime(from.year, from.month, from.day),
      customTo: DateTime(to.year, to.month, to.day, 23, 59, 59),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(usageRepositoryProvider);
    final machines = ref.watch(statusRepositoryProvider).machines;
    final q = snap.query;
    final m = snap.summary?.metrics;
    final machineIds = machines.map((e) => e.machineId).toSet();
    final machineValue =
        (q.machineId != null && machineIds.contains(q.machineId))
            ? q.machineId!
            : '';
    final desktop = isQingyaDesktop;

    Widget filters() => Row(
          children: [
            Expanded(
              child: _DropdownBox<UsageRangePreset>(
                label: '日期',
                value: q.preset,
                items: [
                  for (final p in UsageRangePreset.values)
                    DropdownMenuItem(
                      value: p,
                      child: Text(_presetLabel(p)),
                    ),
                ],
                onChanged: (p) async {
                  if (p == null) return;
                  if (p == UsageRangePreset.custom) {
                    await _pickCustom(q);
                  } else {
                    await _apply(q.copyWith(preset: p));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DropdownBox<String>(
                label: '设备',
                value: machineValue,
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部设备')),
                  for (final machine in machines)
                    DropdownMenuItem(
                      value: machine.machineId,
                      child: Text(
                        machine.machineName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  if (v.isEmpty) {
                    await _apply(q.copyWith(clearMachine: true));
                  } else {
                    await _apply(q.copyWith(machineId: v));
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _DropdownBox<String>(
                label: '渠道',
                value: q.agent ?? '',
                items: const [
                  DropdownMenuItem(value: '', child: Text('全部渠道')),
                  DropdownMenuItem(value: 'claude', child: Text('Claude')),
                  DropdownMenuItem(value: 'codex', child: Text('Codex')),
                ],
                onChanged: (v) async {
                  if (v == null) return;
                  if (v.isEmpty) {
                    await _apply(q.copyWith(clearAgent: true));
                  } else {
                    await _apply(q.copyWith(agent: v));
                  }
                },
              ),
            ),
          ],
        );

    Widget bodyContent() {
      if (snap.loading && m == null) {
        return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      if (snap.error != null && m == null) {
        return EmptyState(
          asset: QingyaAssets.catError,
          title: '用量加载失败',
          subtitle: snap.error!,
        );
      }
      if (m == null || m.eventCount == 0) {
        return const EmptyState(
          asset: QingyaAssets.catEmptyRest,
          title: '这段时间还没有用量',
          subtitle: '确认监控端已开启用量采集并完成同步',
        );
      }

      final hero = _CompactHero(
        realUsage: _fmtInt(m.realUsage),
        cost: _fmtCost(m.estimatedCostUsd, m.priced),
        hitRate: _fmtRate(m.cacheHitRate),
        input: _fmtInt(m.inputTokens),
        output: _fmtInt(m.outputTotal),
        cacheHit: _fmtInt(m.cacheHitTokens),
        events: '${m.eventCount}',
        dense: desktop,
      );
      final note = Text(
        snap.fromCache
            ? '费用为估算 · 当前为本地缓存，下拉可强制刷新'
            : '费用为公开列表价估算，非账单',
        style: TextStyle(
          fontSize: 11,
          color: context.qingya.textSecondary,
        ),
      );
      final heatmap = _ActivityHeatmap(
        data: snap.heatmap,
        fmtInt: _fmtInt,
        desktop: desktop,
      );
      final trend = _TrendCard(
        trend: snap.trend,
        byHour: q.trendByHour,
        bucketed: q.trendBucketed,
        slots: q.trendSlots(),
        fmtInt: _fmtInt,
        fmtRate: _fmtRate,
        fmtCost: _fmtCost,
        desktop: desktop,
      );
      final detailHeader = Row(
        children: [
          Text(
            '明细',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.qingya.textPrimary,
            ),
          ),
          const Spacer(),
          _GroupByToggle(
            value: q.groupBy,
            onChanged: (v) => _apply(q.copyWith(groupBy: v)),
          ),
        ],
      );
      final groups = snap.breakdown?.groups ?? const <UsageBreakdownGroup>[];
      final tiles = [
        for (final g in groups)
          _CompactTile(
            group: g,
            groupBy: q.groupBy,
            expanded: _expanded.contains(g.key),
            onToggle: () {
              setState(() {
                if (!_expanded.add(g.key)) {
                  _expanded.remove(g.key);
                }
              });
            },
            fmtInt: _fmtInt,
            fmtRate: _fmtRate,
            fmtCost: _fmtCost,
          ),
      ];

      if (!desktop) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: 4),
            note,
            const SizedBox(height: 10),
            heatmap,
            const SizedBox(height: 10),
            trend,
            const SizedBox(height: 10),
            detailHeader,
            const SizedBox(height: 8),
            ...tiles,
          ],
        );
      }

      // 桌面：统计条 + 双栏图表（等高）+ 两列明细。
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          hero,
          const SizedBox(height: 6),
          note,
          const SizedBox(height: 12),
          // 热力图保持自然高度；趋势曲线高度对齐热力图格子区（约 200）
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 5, child: heatmap),
              const SizedBox(width: 12),
              Expanded(flex: 6, child: trend),
            ],
          ),
          const SizedBox(height: 14),
          detailHeader,
          const SizedBox(height: 8),
          if (tiles.isEmpty)
            const SizedBox.shrink()
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCol = constraints.maxWidth >= 720;
                if (!twoCol) {
                  return Column(children: tiles);
                }
                final left = <Widget>[];
                final right = <Widget>[];
                for (var i = 0; i < tiles.length; i++) {
                  (i.isEven ? left : right).add(tiles[i]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: left)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(children: right)),
                  ],
                );
              },
            ),
        ],
      );
    }

    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        desktop ? 18 : 12,
        desktop ? 12 : 8,
        desktop ? 18 : 12,
        20,
      ),
      children: [
        Row(
          children: [
            Text(
              'Token 用量',
              style: TextStyle(
                fontSize: desktop ? 22 : 20,
                fontWeight: FontWeight.w800,
                color: context.qingya.textPrimary,
              ),
            ),
            const Spacer(),
            if (snap.fromCache)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '缓存',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.qingya.textSecondary,
                  ),
                ),
              ),
            if (desktop)
              DesktopRefreshButton(
                onRefresh: () => ref
                    .read(usageRepositoryProvider.notifier)
                    .refresh(forceNetwork: true),
              )
            else if (snap.loading)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (desktop)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: filters(),
          )
        else
          filters(),
        const SizedBox(height: 12),
        bodyContent(),
      ],
    );

    Widget body = desktop
        ? Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: kDesktopUsageMaxWidth,
              ),
              child: list,
            ),
          )
        : RefreshIndicator(
            color: context.qingya.primary,
            onRefresh: () => ref
                .read(usageRepositoryProvider.notifier)
                .refresh(forceNetwork: true),
            child: list,
          );

    return Scaffold(
      backgroundColor: context.qingya.scaffold,
      body: SafeArea(
        bottom: false,
        child: body,
      ),
    );
  }
}

class _GroupByToggle extends StatelessWidget {
  const _GroupByToggle({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = <(String, String)>[
    ('model', '模型'),
    ('machine', '设备'),
    ('agent', '渠道'),
    ('project', '项目'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final selected = _options.any((e) => e.$1 == value) ? value : 'model';
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border.withValues(alpha: 0.9)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (key, label) in _options)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    if (key != selected) onChanged(key);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: key == selected ? c.primarySoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            key == selected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            key == selected ? c.primary : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DropdownBox<T> extends StatelessWidget {
  const _DropdownBox({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  String _labelOf(T v) {
    for (final item in items) {
      if (item.value == v) {
        final child = item.child;
        if (child is Text) return child.data ?? label;
        return label;
      }
    }
    return label;
  }

  Future<void> _open(BuildContext context) async {
    final c = context.qingya;
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    // Anchor menu to the closed chip — fixed size, no reflow of the bar.
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight =
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    // Keep popup width identical to the closed chip.
    final menuWidth = box.size.width;

    final selected = await showMenu<T>(
      context: context,
      position: position,
      color: c.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: c.shadow.withValues(alpha: 0.28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border.withValues(alpha: 0.9)),
      ),
      constraints: BoxConstraints(
        minWidth: menuWidth,
        maxWidth: menuWidth,
        maxHeight: 280,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<T>(
            value: item.value,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: DefaultTextStyle(
                    style: TextStyle(
                      fontSize: 13,
                      color: c.textPrimary,
                      fontWeight: item.value == value
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: item.child,
                  ),
                ),
                if (item.value == value)
                  Icon(Icons.check_rounded, size: 16, color: c.device),
              ],
            ),
          ),
      ],
    );
    if (selected != null) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final text = _labelOf(value);

    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context),
        child: Container(
          height: 34,
          padding: const EdgeInsets.only(left: 8, right: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border.withValues(alpha: 0.9)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 16,
                color: c.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactHero extends StatelessWidget {
  const _CompactHero({
    required this.realUsage,
    required this.cost,
    required this.hitRate,
    required this.input,
    required this.output,
    required this.cacheHit,
    required this.events,
    this.dense = false,
  });

  final String realUsage;
  final String cost;
  final String hitRate;
  final String input;
  final String output;
  final String cacheHit;
  final String events;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    if (dense) {
      // 桌面：一行 7 个指标，信息更密，不纵向撑开。
      final cells = <(String, String, Color?, Color?)>[
        ('真实用量', realUsage, null, null),
        ('估算费用', cost, c.device, null),
        ('命中率', hitRate, null, null),
        ('输入', input, c.device, c.deviceSoft),
        ('输出', output, c.working, c.workingSoft),
        ('缓存', cacheHit, c.done, c.doneSoft),
        ('事件', events, c.textSecondary, c.idleSoft),
      ];
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                Container(width: 1, height: 34, color: c.divider),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Column(
                    children: [
                      Text(
                        cells[i].$1,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        cells[i].$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: cells[i].$3 ?? c.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _BigStat(label: '真实用量', value: realUsage)),
              Container(width: 1, height: 36, color: c.divider),
              Expanded(
                child: _BigStat(label: '估算费用', value: cost, accent: true),
              ),
              Container(width: 1, height: 36, color: c.divider),
              Expanded(child: _BigStat(label: '命中率', value: hitRate)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SmallStat(
                label: '输入',
                value: input,
                bg: c.deviceSoft,
                fg: c.device,
              ),
              _SmallStat(
                label: '输出',
                value: output,
                bg: c.workingSoft,
                fg: c.working,
              ),
              _SmallStat(
                label: '缓存',
                value: cacheHit,
                bg: c.doneSoft,
                fg: c.done,
              ),
              _SmallStat(
                label: '事件',
                value: events,
                bg: c.idleSoft,
                fg: c.textSecondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({
    required this.label,
    required this.value,
    this.accent = false,
  });
  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.qingya.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: accent ? context.qingya.device : context.qingya.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
  });
  final String label;
  final String value;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: fg.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// GitHub 风格活跃热力图（紧凑，高度接近汇总卡）。
class _ActivityHeatmap extends StatefulWidget {
  const _ActivityHeatmap({
    required this.data,
    required this.fmtInt,
    this.desktop = false,
  });

  final UsageBreakdown? data;
  final String Function(int) fmtInt;
  final bool desktop;

  @override
  State<_ActivityHeatmap> createState() => _ActivityHeatmapState();
}

class _ActivityHeatmapState extends State<_ActivityHeatmap> {
  /// 移动端点击后显示在标题旁；桌面端用 Tooltip 悬停。
  String? _tip;

  /// 服务端按 UTC 日切桶；用本地中午映射。
  String _dayKey(DateTime localDay) {
    final mid =
        DateTime(localDay.year, localDay.month, localDay.day, 12).toUtc();
    final y = mid.year.toString().padLeft(4, '0');
    final m = mid.month.toString().padLeft(2, '0');
    final d = mid.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  List<Color> _scaleColors() {
    final c = context.qingya;
    return [
      c.idleSoft,
      Color.lerp(c.idleSoft, c.primary, 0.32)!,
      Color.lerp(c.idleSoft, c.primary, 0.55)!,
      Color.lerp(c.primary, c.primaryDark, 0.45)!,
      c.primaryDark,
    ];
  }

  int _scaleCap(Iterable<int> values) {
    final positives = values.where((v) => v > 0).toList()..sort();
    if (positives.isEmpty) return 0;
    if (positives.length == 1) return positives.first;
    final idx =
        ((positives.length - 1) * 0.90).round().clamp(0, positives.length - 1);
    final p90 = positives[idx];
    return p90 <= 0 ? positives.last : p90;
  }

  Color _colorFor(int value, int cap) {
    final levels = _scaleColors();
    if (value <= 0 || cap <= 0) return levels[0];
    final t = (value / cap).clamp(0.0, 1.0);
    final idx = (1 + (t * 3.999).floor()).clamp(1, 4);
    return levels[idx];
  }

  String _cellTip(DateTime day, int v) {
    final label =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    if (v <= 0) return '$label · 无用量';
    return '$label · ${widget.fmtInt(v)}';
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final end = DateTime(n.year, n.month, n.day);
    // 以「本周周一」为最右周起点，向前 16 周 —— 始终包含最新一周
    const weeks = 16;
    final thisWeekMonday = end.subtract(Duration(days: end.weekday - 1));
    final gridStart =
        thisWeekMonday.subtract(const Duration(days: (weeks - 1) * 7));
    final byKey = <String, int>{
      for (final g in widget.data?.groups ?? const <UsageBreakdownGroup>[])
        g.key: g.metrics.realUsage,
    };

    final cells = <({DateTime day, int value})>[];
    final positiveValues = <int>[];
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < 7; d++) {
        final day = gridStart.add(Duration(days: w * 7 + d));
        if (day.isAfter(end)) {
          cells.add((day: day, value: -1)); // 未来空
          continue;
        }
        final v = byKey[_dayKey(day)] ?? 0;
        if (v > 0) positiveValues.add(v);
        cells.add((day: day, value: v));
      }
    }
    final cap = _scaleCap(positiveValues);
    final desktop = widget.desktop;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.qingya.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.qingya.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '活跃热力',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.qingya.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                desktop
                    ? '近 16 周 · 悬停查看'
                    : (_tip ?? '近 16 周 · 点格子查看'),
                style: TextStyle(
                  fontSize: 11,
                  color: context.qingya.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, c) {
              const gap = 2.5;
              final cell = ((c.maxWidth - gap * (weeks - 1)) / weeks)
                  .clamp(8.0, 28.0);
              final height = cell * 7 + gap * 6;
              return SizedBox(
                width: c.maxWidth,
                height: height,
                child: Row(
                  children: [
                    for (var w = 0; w < weeks; w++) ...[
                      if (w > 0) SizedBox(width: gap),
                      Expanded(
                        child: Column(
                          children: [
                            for (var d = 0; d < 7; d++) ...[
                              if (d > 0) SizedBox(height: gap),
                              Expanded(
                                child: Builder(
                                  builder: (_) {
                                    final cellData = cells[w * 7 + d];
                                    final v = cellData.value;
                                    final empty = v < 0;
                                    final color = empty
                                        ? Colors.transparent
                                        : _colorFor(v, cap);
                                    final box = Container(
                                      decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(2),
                                        border: empty
                                            ? null
                                            : Border.all(
                                                color: context.qingya.border
                                                    .withValues(alpha: 0.45),
                                                width: 0.5,
                                              ),
                                      ),
                                    );
                                    if (empty) return box;
                                    final tip = _cellTip(cellData.day, v);
                                    if (desktop) {
                                      return Tooltip(
                                        message: tip,
                                        waitDuration:
                                            const Duration(milliseconds: 120),
                                        preferBelow: true,
                                        child: box,
                                      );
                                    }
                                    return GestureDetector(
                                      onTap: () => setState(() => _tip = tip),
                                      child: box,
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '少',
                style: TextStyle(
                  fontSize: 10,
                  color: context.qingya.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              for (final c in _scaleColors()) ...[
                Container(
                  width: 9,
                  height: 9,
                  margin: const EdgeInsets.only(right: 3),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              Text(
                '多',
                style: TextStyle(
                  fontSize: 10,
                  color: context.qingya.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.trend,
    required this.byHour,
    this.bucketed = false,
    required this.slots,
    required this.fmtInt,
    required this.fmtRate,
    required this.fmtCost,
    this.desktop = false,
  });

  final UsageBreakdown? trend;
  final bool byHour;
  /// When true, [slots] are bucket starts; aggregate daily metrics into each bucket.
  final bool bucketed;
  /// 本地时区整点/整日槽位（或桶起点）。
  final List<DateTime> slots;
  final String Function(int) fmtInt;
  final String Function(double?) fmtRate;
  final String Function(double?, bool) fmtCost;
  final bool desktop;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selected;
  Offset? _hoverLocal;

  /// 服务端按 UTC 切桶：YYYY-MM-DDTHH / YYYY-MM-DD
  String _serverHourKey(DateTime localSlot) {
    final u = localSlot.toUtc();
    final y = u.year.toString().padLeft(4, '0');
    final m = u.month.toString().padLeft(2, '0');
    final d = u.day.toString().padLeft(2, '0');
    final h = u.hour.toString().padLeft(2, '0');
    return '$y-$m-${d}T$h';
  }

  String _serverDayKey(DateTime localDay) {
    // 服务端按 UTC 日期切桶；用本地中午映射，减少跨日边界误差。
    final mid = DateTime(localDay.year, localDay.month, localDay.day, 12);
    final uu = mid.toUtc();
    final y = uu.year.toString().padLeft(4, '0');
    final m = uu.month.toString().padLeft(2, '0');
    final d = uu.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }


  DateTime? _parseServerDayKey(String key) {
    // YYYY-MM-DD
    if (key.length < 10) return null;
    final y = int.tryParse(key.substring(0, 4));
    final m = int.tryParse(key.substring(5, 7));
    final d = int.tryParse(key.substring(8, 10));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  List<DateTime> _evenBucketStarts(DateTime start, DateTime end, int buckets) {
    if (buckets <= 1) return [start];
    final totalDays = end.difference(start).inDays + 1;
    if (totalDays <= 0) return [start];
    if (totalDays <= buckets) {
      return [
        for (var i = 0; i < totalDays; i++) start.add(Duration(days: i)),
      ];
    }
    return [
      for (var i = 0; i < buckets; i++)
        start.add(Duration(days: (i * totalDays / buckets).floor())),
    ];
  }

  UsageMetrics _sumMetrics(Iterable<UsageMetrics> list) {
    var input = 0, output = 0, reasoning = 0, cw = 0, ch = 0, real = 0, events = 0;
    double cost = 0;
    var hasCost = false;
    var priced = false;
    for (final m in list) {
      input += m.inputTokens;
      output += m.outputTokens;
      reasoning += m.reasoningTokens;
      cw += m.cacheWriteTokens;
      ch += m.cacheHitTokens;
      real += m.realUsage;
      events += m.eventCount;
      if (m.estimatedCostUsd != null) {
        cost += m.estimatedCostUsd!;
        hasCost = true;
      }
      if (m.priced) priced = true;
    }
    final denom = ch + input;
    return UsageMetrics(
      inputTokens: input,
      outputTokens: output,
      reasoningTokens: reasoning,
      cacheWriteTokens: cw,
      cacheHitTokens: ch,
      realUsage: real,
      cacheHitRate: denom > 0 ? ch / denom : null,
      estimatedCostUsd: hasCost ? cost : null,
      eventCount: events,
      priced: priced,
    );
  }

  List<_TrendPoint> _buildPoints() {
    final raw = [...(widget.trend?.groups ?? const <UsageBreakdownGroup>[])];
    final byKey = <String, UsageMetrics>{
      for (final g in raw) g.key: g.metrics,
    };

    if (widget.bucketed) {
      // Start from first day that actually has data → today, then 20 buckets.
      final dataDays = <DateTime>[];
      for (final e in byKey.entries) {
        final m = e.value;
        if (m.realUsage <= 0 && m.eventCount <= 0 && m.inputTokens <= 0) {
          continue;
        }
        final parsed = _parseServerDayKey(e.key);
        if (parsed != null) dataDays.add(parsed);
      }
      if (dataDays.isEmpty) {
        return const <_TrendPoint>[];
      }
      dataDays.sort();
      // If idle gap > 30 days appears, drop earlier sparse segment(s);
      // keep only from the first data day after the last long gap → today.
      var start = DateTime(dataDays.first.year, dataDays.first.month, dataDays.first.day);
      for (var i = 1; i < dataDays.length; i++) {
        final prev = dataDays[i - 1];
        final cur = dataDays[i];
        final gapDays = cur.difference(prev).inDays;
        if (gapDays > 30) {
          start = DateTime(cur.year, cur.month, cur.day);
        }
      }
      final now = DateTime.now();
      final endDay = DateTime(now.year, now.month, now.day);
      final slots = _evenBucketStarts(start, endDay, 20);
      final lastEnd = endDay.add(const Duration(days: 1));
      final out = <_TrendPoint>[];
      for (var i = 0; i < slots.length; i++) {
        final bStart = slots[i];
        final bEnd = i + 1 < slots.length ? slots[i + 1] : lastEnd;
        final bucket = <UsageMetrics>[];
        var day = bStart;
        while (day.isBefore(bEnd)) {
          final m = byKey[_serverDayKey(day)];
          if (m != null) bucket.add(m);
          day = day.add(const Duration(days: 1));
        }
        final endLabel = bEnd.subtract(const Duration(days: 1));
        out.add(
          _TrendPoint(
            label: '${bStart.month}/${bStart.day}',
            title:
                '${bStart.year}-${bStart.month.toString().padLeft(2, '0')}-${bStart.day.toString().padLeft(2, '0')}'
                ' ~ '
                '${endLabel.year}-${endLabel.month.toString().padLeft(2, '0')}-${endLabel.day.toString().padLeft(2, '0')}',
            metrics: _sumMetrics(bucket),
          ),
        );
      }
      return out;
    }

    // 严格按本地槽位补齐：今天 0:00→当前整点；近1天 24 个整点。
    return [
      for (final slot in widget.slots)
        _TrendPoint(
          label: widget.byHour
              ? '${slot.hour.toString().padLeft(2, '0')}:00'
              : '${slot.month.toString().padLeft(2, '0')}-${slot.day.toString().padLeft(2, '0')}',
          title: widget.byHour
              ? '${slot.month.toString().padLeft(2, '0')}-${slot.day.toString().padLeft(2, '0')} '
                  '${slot.hour.toString().padLeft(2, '0')}:00'
              : '${slot.year}-${slot.month.toString().padLeft(2, '0')}-${slot.day.toString().padLeft(2, '0')}',
          metrics: byKey[widget.byHour
                  ? _serverHourKey(slot)
                  : _serverDayKey(slot)] ??
              const UsageMetrics(),
        ),
    ];
  }

  void _selectFromLocalX(
    double localX,
    double width,
    int n, {
    Offset? hover,
  }) {
    if (n <= 0 || width <= 0) return;
    const padL = 4.0;
    const padR = 4.0;
    final w = width - padL - padR;
    final x = localX.clamp(padL, padL + w);
    final idx = n == 1
        ? 0
        : ((x - padL) / w * (n - 1)).round().clamp(0, n - 1);
    if (_selected == idx &&
        (hover == null || _hoverLocal == hover)) {
      return;
    }
    setState(() {
      _selected = idx;
      if (hover != null) _hoverLocal = hover;
    });
  }

  Widget _detailChip(String k, String v) {
    return Text(
      '$k $v',
      style: TextStyle(
        fontSize: 11,
        color: context.qingya.textPrimary,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _hoverPanel(_TrendPoint selected) {
    final c = context.qingya;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(10),
      color: c.card,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 3,
              children: [
                _detailChip(
                  '真实用量',
                  widget.fmtInt(selected.metrics.realUsage),
                ),
                _detailChip(
                  '输入',
                  widget.fmtInt(selected.metrics.inputTokens),
                ),
                _detailChip(
                  '输出',
                  widget.fmtInt(selected.metrics.outputTotal),
                ),
                _detailChip(
                  '缓存',
                  widget.fmtInt(selected.metrics.cacheHitTokens),
                ),
                _detailChip('事件', '${selected.metrics.eventCount}'),
                _detailChip(
                  '命中率',
                  widget.fmtRate(selected.metrics.cacheHitRate),
                ),
                _detailChip(
                  '费用',
                  widget.fmtCost(
                    selected.metrics.estimatedCostUsd,
                    selected.metrics.priced,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<_TrendPoint> points, {required bool expand}) {
    final chart = points.isEmpty
        ? Center(
            child: Text(
              '暂无趋势数据',
              style: TextStyle(
                fontSize: 12,
                color: context.qingya.textSecondary,
              ),
            ),
          )
        : LayoutBuilder(
            builder: (context, constraints) {
              final desktop = widget.desktop;
              final selected = (_selected != null &&
                      _selected! >= 0 &&
                      _selected! < points.length)
                  ? points[_selected!]
                  : null;

              Widget paint = CustomPaint(
                painter: _TrendPainter(
                  points: points,
                  selected: _selected,
                  palette: context.qingya,
                ),
                child: const SizedBox.expand(),
              );

              if (desktop) {
                paint = MouseRegion(
                  opaque: true,
                  onHover: (e) {
                    _selectFromLocalX(
                      e.localPosition.dx,
                      constraints.maxWidth,
                      points.length,
                      hover: e.localPosition,
                    );
                  },
                  onExit: (_) {
                    setState(() {
                      _selected = null;
                      _hoverLocal = null;
                    });
                  },
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      paint,
                      if (selected != null && _hoverLocal != null)
                        Positioned(
                          left: (_hoverLocal!.dx + 12).clamp(
                            0.0,
                            math.max(0.0, constraints.maxWidth - 220),
                          ),
                          top: (_hoverLocal!.dy - 8).clamp(
                            0.0,
                            math.max(0.0, constraints.maxHeight - 96),
                          ),
                          child: IgnorePointer(child: _hoverPanel(selected)),
                        ),
                    ],
                  ),
                );
              } else {
                paint = GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _selectFromLocalX(
                    d.localPosition.dx,
                    constraints.maxWidth,
                    points.length,
                  ),
                  onHorizontalDragUpdate: (d) => _selectFromLocalX(
                    d.localPosition.dx,
                    constraints.maxWidth,
                    points.length,
                  ),
                  child: paint,
                );
              }
              return paint;
            },
          );

    // 桌面：曲线区高度对齐热力图格子（7 行 × ~28 + 间距 ≈ 200）
    // 移动：保持原先 120
    final h = expand ? 200.0 : 120.0;
    return SizedBox(height: h, child: chart);
  }

  @override
  Widget build(BuildContext context) {
    final points = _buildPoints();
    final selected = (_selected != null &&
            _selected! >= 0 &&
            _selected! < points.length)
        ? points[_selected!]
        : null;
    final desktop = widget.desktop;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: context.qingya.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.qingya.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.byHour
                    ? '用量趋势（按小时）'
                    : (widget.bucketed ? '用量趋势（分桶）' : '用量趋势（按天）'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.qingya.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                desktop
                    ? '悬停查看详情'
                    : (widget.byHour
                        ? '${points.length} 个时点'
                        : (widget.bucketed
                            ? '${points.length} 段'
                            : '${points.length} 天')),
                style: TextStyle(
                  fontSize: 11,
                  color: context.qingya.textSecondary,
                ),
              ),
            ],
          ),
          if (!desktop) ...[
            const SizedBox(height: 4),
            Text(
              '点击/拖动曲线节点查看详情',
              style: TextStyle(
                fontSize: 11,
                color: context.qingya.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _buildChart(points, expand: desktop),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  points.first.label,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.qingya.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '峰值 ${widget.fmtInt(points.map((e) => e.value).reduce(math.max))}',
                  style: TextStyle(
                    fontSize: 10,
                    color: context.qingya.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  points.last.label,
                  style: TextStyle(
                    fontSize: 10,
                    color: context.qingya.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          // 移动端保留底部详情面板；桌面端信息只在悬停浮层
          if (!desktop && selected != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.qingya.primarySoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.qingya.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _detailChip(
                        '真实用量',
                        widget.fmtInt(selected.metrics.realUsage),
                      ),
                      _detailChip(
                        '输入',
                        widget.fmtInt(selected.metrics.inputTokens),
                      ),
                      _detailChip(
                        '输出',
                        widget.fmtInt(selected.metrics.outputTotal),
                      ),
                      _detailChip(
                        '缓存',
                        widget.fmtInt(selected.metrics.cacheHitTokens),
                      ),
                      _detailChip('事件', '${selected.metrics.eventCount}'),
                      _detailChip(
                        '命中率',
                        widget.fmtRate(selected.metrics.cacheHitRate),
                      ),
                      _detailChip(
                        '费用',
                        widget.fmtCost(
                          selected.metrics.estimatedCostUsd,
                          selected.metrics.priced,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendPoint {
  const _TrendPoint({
    required this.label,
    required this.title,
    required this.metrics,
  });
  final String label;
  final String title;
  final UsageMetrics metrics;
  int get value => metrics.realUsage;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.selected,
    required this.palette,
  });
  final List<_TrendPoint> points;
  final int? selected;
  final QingyaPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final maxV =
        math.max(1, points.map((e) => e.value).fold<int>(0, math.max)).toDouble();
    const padL = 4.0;
    const padR = 4.0;
    const padT = 8.0;
    const padB = 6.0;
    final w = size.width - padL - padR;
    final h = size.height - padT - padB;

    final grid = Paint()
      ..color = palette.divider
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = padT + h * i / 2;
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), grid);
    }

    final n = points.length;
    Offset pt(int i) {
      final x = padL + (n == 1 ? w / 2 : w * i / (n - 1));
      final t = points[i].value / maxV;
      final y = padT + h * (1 - t);
      return Offset(x, y);
    }

    if (selected != null && selected! >= 0 && selected! < n) {
      final sp = pt(selected!);
      canvas.drawLine(
        Offset(sp.dx, padT),
        Offset(sp.dx, padT + h),
        Paint()
          ..color = palette.primary.withValues(alpha: 0.35)
          ..strokeWidth = 1.2,
      );
    }

    final path = Path();
    final fill = Path();
    for (var i = 0; i < n; i++) {
      final p = pt(i);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
        fill.moveTo(p.dx, padT + h);
        fill.lineTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
        fill.lineTo(p.dx, p.dy);
      }
    }
    fill.lineTo(pt(n - 1).dx, padT + h);
    fill.close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.primary.withValues(alpha: 0.28),
            palette.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dot = Paint()..color = palette.primaryDark;
    for (var i = 0; i < n; i++) {
      final p = pt(i);
      final active = selected == i;
      canvas.drawCircle(p, active ? 4.5 : 2.4, dot);
      if (active) {
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = palette.primary.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.selected != selected || oldDelegate.palette != palette;
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.group,
    this.groupBy = '',
    required this.expanded,
    required this.onToggle,
    required this.fmtInt,
    required this.fmtRate,
    required this.fmtCost,
  });

  final UsageBreakdownGroup group;
  final String groupBy;
  final bool expanded;
  final VoidCallback onToggle;
  final String Function(int) fmtInt;
  final String Function(double?) fmtRate;
  final String Function(double?, bool) fmtCost;

  static const _projectSep = '';

  @override
  Widget build(BuildContext context) {
    final m = group.metrics;
    final c = context.qingya;
    final rawKey = group.key.isEmpty ? 'unknown' : group.key;
    String title = rawKey;
    String? subtitle;
    if (groupBy == 'project' || rawKey.contains(_projectSep)) {
      final parts = rawKey.split(_projectSep);
      title = parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : 'unknown';
      subtitle = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : '未知项目';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: c.textSecondary,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      fmtInt(m.realUsage),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.primaryDark,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: c.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '入${fmtInt(m.inputTokens)} · 出${fmtInt(m.outputTotal)} · 命中${fmtRate(m.cacheHitRate)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      fmtCost(m.estimatedCostUsd, m.priced),
                      style: TextStyle(
                        fontSize: 11,
                        color: c.device,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 6),
                  _kv(context, '新增输入', fmtInt(m.inputTokens)),
                  _kv(context, '输出', fmtInt(m.outputTokens)),
                  if (m.reasoningTokens > 0)
                    _kv(context, '推理', fmtInt(m.reasoningTokens)),
                  _kv(context, '缓存命中', fmtInt(m.cacheHitTokens)),
                  _kv(context, '缓存写入', fmtInt(m.cacheWriteTokens)),
                  _kv(context, '事件', '${m.eventCount}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    final c = context.qingya;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(k,
              style: TextStyle(fontSize: 11, color: c.textSecondary)),
          const Spacer(),
          Text(v,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary)),
        ],
      ),
    );
  }
}
