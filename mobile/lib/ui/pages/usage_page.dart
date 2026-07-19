import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repo/status_repository.dart';
import '../../data/repo/usage_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
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

    return Scaffold(
      backgroundColor: QingyaColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: QingyaColors.primary,
          onRefresh: () => ref
              .read(usageRepositoryProvider.notifier)
              .refresh(forceNetwork: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
            children: [
              Row(
                children: [
                  const Text(
                    'Token 用量',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: QingyaColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (snap.fromCache)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text(
                        '缓存',
                        style: TextStyle(
                          fontSize: 11,
                          color: QingyaColors.textSecondary,
                        ),
                      ),
                    ),
                  if (snap.loading)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              // 筛选：下拉
              Row(
                children: [
                  Expanded(
                    child: _DropdownBox<UsageRangePreset>(
                      label: '时间',
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
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
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
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DropdownBox<String>(
                      label: '明细',
                      value: q.groupBy,
                      items: const [
                        DropdownMenuItem(value: 'model', child: Text('按模型')),
                        DropdownMenuItem(value: 'agent', child: Text('按渠道')),
                        DropdownMenuItem(value: 'machine', child: Text('按设备')),
                      ],
                      onChanged: (v) async {
                        if (v == null) return;
                        await _apply(q.copyWith(groupBy: v));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (snap.loading && m == null)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (snap.error != null && m == null)
                EmptyState(
                  asset: QingyaAssets.catError,
                  title: '用量加载失败',
                  subtitle: snap.error!,
                )
              else if (m == null || m.eventCount == 0)
                const EmptyState(
                  asset: QingyaAssets.catEmptyRest,
                  title: '这段时间还没有用量',
                  subtitle: '确认监控端已开启用量采集并完成同步',
                )
              else ...[
                _CompactHero(
                  realUsage: _fmtInt(m.realUsage),
                  cost: _fmtCost(m.estimatedCostUsd, m.priced),
                  hitRate: _fmtRate(m.cacheHitRate),
                  input: _fmtInt(m.inputTokens),
                  output: _fmtInt(m.outputTotal),
                  cacheHit: _fmtInt(m.cacheHitTokens),
                  events: '${m.eventCount}',
                ),
                const SizedBox(height: 4),
                Text(
                  snap.fromCache
                      ? '费用为估算 · 当前为本地缓存，下拉可强制刷新'
                      : '费用为公开列表价估算，非账单',
                  style: const TextStyle(
                    fontSize: 11,
                    color: QingyaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                _TrendCard(
                  trend: snap.trend,
                  byHour: q.trendByHour,
                  slots: q.trendSlots(),
                  fmtInt: _fmtInt,
                  fmtRate: _fmtRate,
                  fmtCost: _fmtCost,
                ),
                const SizedBox(height: 10),
                const Text(
                  '明细',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: QingyaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final g
                    in snap.breakdown?.groups ?? const <UsageBreakdownGroup>[])
                  _CompactTile(
                    group: g,
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
              ],
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    // Force light menu even if system/app dark theme leaks into popup.
    final lightMenu = Theme.of(context).copyWith(
      brightness: Brightness.light,
      canvasColor: QingyaColors.card,
      colorScheme: const ColorScheme.light(
        primary: QingyaColors.primary,
        onPrimary: Colors.white,
        surface: QingyaColors.card,
        onSurface: QingyaColors.textPrimary,
      ),
      dropdownMenuTheme: const DropdownMenuThemeData(
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(QingyaColors.card),
        ),
      ),
    );

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QingyaColors.border),
      ),
      child: Theme(
        data: lightMenu,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: value,
            dropdownColor: QingyaColors.card,
            focusColor: QingyaColors.primarySoft,
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: QingyaColors.textSecondary,
            ),
            style: const TextStyle(
              fontSize: 13,
              color: QingyaColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            borderRadius: BorderRadius.circular(12),
            items: [
              for (final item in items)
                DropdownMenuItem<T>(
                  value: item.value,
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 13,
                      color: QingyaColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                    child: item.child,
                  ),
                ),
            ],
            onChanged: onChanged,
            hint: Text(
              label,
              style: const TextStyle(color: QingyaColors.textSecondary),
            ),
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
  });

  final String realUsage;
  final String cost;
  final String hitRate;
  final String input;
  final String output;
  final String cacheHit;
  final String events;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QingyaColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _BigStat(label: '真实用量', value: realUsage)),
              Container(width: 1, height: 36, color: QingyaColors.divider),
              Expanded(
                child: _BigStat(label: '估算费用', value: cost, accent: true),
              ),
              Container(width: 1, height: 36, color: QingyaColors.divider),
              Expanded(child: _BigStat(label: '命中率', value: hitRate)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _SmallStat(
                label: '输入',
                value: input,
                bg: const Color(0xFFE8F0FF),
                fg: QingyaColors.device,
              ),
              _SmallStat(
                label: '输出',
                value: output,
                bg: const Color(0xFFFFF1DF),
                fg: QingyaColors.working,
              ),
              _SmallStat(
                label: '缓存',
                value: cacheHit,
                bg: const Color(0xFFE7F7EC),
                fg: QingyaColors.done,
              ),
              _SmallStat(
                label: '事件',
                value: events,
                bg: const Color(0xFFF3EEEA),
                fg: QingyaColors.textSecondary,
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
          style: const TextStyle(fontSize: 11, color: QingyaColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: accent ? QingyaColors.device : QingyaColors.textPrimary,
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

class _TrendCard extends StatefulWidget {
  const _TrendCard({
    required this.trend,
    required this.byHour,
    required this.slots,
    required this.fmtInt,
    required this.fmtRate,
    required this.fmtCost,
  });

  final UsageBreakdown? trend;
  final bool byHour;
  /// 本地时区整点/整日槽位。
  final List<DateTime> slots;
  final String Function(int) fmtInt;
  final String Function(double?) fmtRate;
  final String Function(double?, bool) fmtCost;

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int? _selected;

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

  List<_TrendPoint> _buildPoints() {
    final raw = [...(widget.trend?.groups ?? const <UsageBreakdownGroup>[])];
    final byKey = <String, UsageMetrics>{
      for (final g in raw) g.key: g.metrics,
    };

    // 严格按本地槽位补齐：今天 0:00→当前整点；近1天 24 个整点。
    // 数据用本地槽位对应的 UTC key 去匹配服务端。
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

  void _selectFromLocalX(double localX, double width, int n) {
    if (n <= 0 || width <= 0) return;
    const padL = 4.0;
    const padR = 4.0;
    final w = width - padL - padR;
    final x = localX.clamp(padL, padL + w);
    final idx = n == 1
        ? 0
        : ((x - padL) / w * (n - 1)).round().clamp(0, n - 1);
    setState(() => _selected = idx);
  }

  @override
  Widget build(BuildContext context) {
    final points = _buildPoints();
    final selected = (_selected != null &&
            _selected! >= 0 &&
            _selected! < points.length)
        ? points[_selected!]
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: QingyaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.byHour ? '用量趋势（按小时）' : '用量趋势（按天）',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: QingyaColors.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                widget.byHour
                    ? '${points.length} 个时点'
                    : '${points.length} 天',
                style: const TextStyle(
                  fontSize: 11,
                  color: QingyaColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '点击/拖动曲线节点查看详情',
            style: TextStyle(fontSize: 11, color: QingyaColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: points.isEmpty
                ? const Center(
                    child: Text(
                      '暂无趋势数据',
                      style: TextStyle(
                        fontSize: 12,
                        color: QingyaColors.textSecondary,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
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
                        child: CustomPaint(
                          painter: _TrendPainter(
                            points: points,
                            selected: _selected,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      );
                    },
                  ),
          ),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  points.first.label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: QingyaColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  '峰值 ${widget.fmtInt(points.map((e) => e.value).reduce(math.max))}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: QingyaColors.textSecondary,
                  ),
                ),
                const Spacer(),
                Text(
                  points.last.label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: QingyaColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: QingyaColors.primarySoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selected.title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: QingyaColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _tip('真实用量', widget.fmtInt(selected.metrics.realUsage)),
                      _tip('输入', widget.fmtInt(selected.metrics.inputTokens)),
                      _tip(
                        '输出',
                        widget.fmtInt(selected.metrics.outputTotal),
                      ),
                      _tip(
                        '缓存',
                        widget.fmtInt(selected.metrics.cacheHitTokens),
                      ),
                      _tip('事件', '${selected.metrics.eventCount}'),
                      _tip(
                        '命中率',
                        widget.fmtRate(selected.metrics.cacheHitRate),
                      ),
                      _tip(
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

  Widget _tip(String k, String v) {
    return Text(
      '$k $v',
      style: const TextStyle(
        fontSize: 11,
        color: QingyaColors.textPrimary,
        fontWeight: FontWeight.w600,
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
  _TrendPainter({required this.points, required this.selected});
  final List<_TrendPoint> points;
  final int? selected;

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
      ..color = QingyaColors.divider
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
          ..color = QingyaColors.primary.withValues(alpha: 0.35)
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
            QingyaColors.primary.withValues(alpha: 0.28),
            QingyaColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = QingyaColors.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final dot = Paint()..color = QingyaColors.primaryDark;
    for (var i = 0; i < n; i++) {
      final p = pt(i);
      final active = selected == i;
      canvas.drawCircle(p, active ? 4.5 : 2.4, dot);
      if (active) {
        canvas.drawCircle(
          p,
          7,
          Paint()
            ..color = QingyaColors.primary.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.selected != selected;
}

class _CompactTile extends StatelessWidget {
  const _CompactTile({
    required this.group,
    required this.expanded,
    required this.onToggle,
    required this.fmtInt,
    required this.fmtRate,
    required this.fmtCost,
  });

  final UsageBreakdownGroup group;
  final bool expanded;
  final VoidCallback onToggle;
  final String Function(int) fmtInt;
  final String Function(double?) fmtRate;
  final String Function(double?, bool) fmtCost;

  @override
  Widget build(BuildContext context) {
    final m = group.metrics;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        group.key.isEmpty ? 'unknown' : group.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: QingyaColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      fmtInt(m.realUsage),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: QingyaColors.primaryDark,
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 18,
                      color: QingyaColors.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '入${fmtInt(m.inputTokens)} · 出${fmtInt(m.outputTotal)} · 命中${fmtRate(m.cacheHitRate)}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: QingyaColors.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      fmtCost(m.estimatedCostUsd, m.priced),
                      style: const TextStyle(
                        fontSize: 11,
                        color: QingyaColors.device,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (expanded) ...[
                  const SizedBox(height: 6),
                  _kv('新增输入', fmtInt(m.inputTokens)),
                  _kv('输出', fmtInt(m.outputTokens)),
                  if (m.reasoningTokens > 0)
                    _kv('推理', fmtInt(m.reasoningTokens)),
                  _kv('缓存命中', fmtInt(m.cacheHitTokens)),
                  _kv('缓存写入', fmtInt(m.cacheWriteTokens)),
                  _kv('事件', '${m.eventCount}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text(k,
              style: const TextStyle(
                  fontSize: 11, color: QingyaColors.textSecondary)),
          const Spacer(),
          Text(v,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: QingyaColors.textPrimary)),
        ],
      ),
    );
  }
}
