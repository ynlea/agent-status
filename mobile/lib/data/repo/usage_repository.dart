import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../api/rest_client.dart';
import '../prefs/settings_store.dart';
import 'status_repository.dart';
import 'usage_cache.dart';

enum UsageRangePreset { today, day1, day7, day30, all, custom }

class UsageQueryState {
  const UsageQueryState({
    this.preset = UsageRangePreset.today,
    this.customFrom,
    this.customTo,
    this.machineId,
    this.agent,
    this.groupBy = 'model',
  });

  final UsageRangePreset preset;
  final DateTime? customFrom;
  final DateTime? customTo;
  final String? machineId;
  final String? agent;
  final String groupBy;

  UsageQueryState copyWith({
    UsageRangePreset? preset,
    DateTime? customFrom,
    DateTime? customTo,
    String? machineId,
    bool clearMachine = false,
    String? agent,
    bool clearAgent = false,
    String? groupBy,
  }) {
    return UsageQueryState(
      preset: preset ?? this.preset,
      customFrom: customFrom ?? this.customFrom,
      customTo: customTo ?? this.customTo,
      machineId: clearMachine ? null : (machineId ?? this.machineId),
      agent: clearAgent ? null : (agent ?? this.agent),
      groupBy: groupBy ?? this.groupBy,
    );
  }

  /// API / 汇总时间窗（本地时区）。
  /// - 今天：当天 00:00 → 现在
  /// - 近1天：现在往前滚 24 小时 → 现在
  (DateTime, DateTime) window([DateTime? now]) {
    final n = now ?? DateTime.now();
    switch (preset) {
      case UsageRangePreset.today:
        final start = DateTime(n.year, n.month, n.day);
        return (start, n);
      case UsageRangePreset.day1:
        return (n.subtract(const Duration(hours: 24)), n);
      case UsageRangePreset.day7:
        return (n.subtract(const Duration(days: 7)), n);
      case UsageRangePreset.day30:
        return (n.subtract(const Duration(days: 30)), n);
      case UsageRangePreset.all:
        // Earliest practical bound; server returns whatever exists.
        return (DateTime(2024, 1, 1), n);
      case UsageRangePreset.custom:
        final from = customFrom ?? DateTime(n.year, n.month, n.day);
        final to = customTo ?? n;
        return (from, to.isBefore(from) ? from : to);
    }
  }

  /// 趋势图 API 窗口与汇总一致。
  (DateTime, DateTime) trendWindow([DateTime? now]) => window(now);

  /// 趋势横轴槽位（本地整点 / 本地日）。
  /// - 今天：00:00 … 当前整点（含）
  /// - 近1天：当前整点往前共 24 个整点
  List<DateTime> trendSlots([DateTime? now]) {
    final n = now ?? DateTime.now();
    if (trendByHour) {
      final end = DateTime(n.year, n.month, n.day, n.hour);
      if (preset == UsageRangePreset.today) {
        final start = DateTime(n.year, n.month, n.day);
        final out = <DateTime>[];
        var t = start;
        while (!t.isAfter(end)) {
          out.add(t);
          t = t.add(const Duration(hours: 1));
        }
        return out;
      }
      // 近1天或其它 ≤24h：滚动 24 个整点
      final start = end.subtract(const Duration(hours: 23));
      return [
        for (var i = 0; i < 24; i++) start.add(Duration(hours: i)),
      ];
    }
    final (from, to) = window(n);
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    // 「全部」压成固定 20 个桶，避免曲线点过密。
    if (preset == UsageRangePreset.all) {
      return _evenBucketStarts(start, end, 20);
    }
    final out = <DateTime>[];
    var t = start;
    while (!t.isAfter(end) && out.length < 90) {
      out.add(t);
      t = t.add(const Duration(days: 1));
    }
    return out;
  }

  /// Evenly spaced bucket start days in [start, end] (inclusive day range).
  static List<DateTime> _evenBucketStarts(DateTime start, DateTime end, int buckets) {
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

  bool get trendBucketed => preset == UsageRangePreset.all && !trendByHour;

  /// ≤ 1 天 → 按小时；更长 → 按天。
  bool get trendByHour {
    final (from, to) = window();
    return !to.difference(from).isNegative &&
        to.difference(from) <= const Duration(hours: 24);
  }

  String get trendGroupBy => trendByHour ? 'hour' : 'day';
}

class UsageSnapshot {
  const UsageSnapshot({
    this.query = const UsageQueryState(),
    this.summary,
    this.breakdown,
    this.trend,
    this.heatmap,
    this.loading = false,
    this.fromCache = false,
    this.error,
  });

  final UsageQueryState query;
  final UsageSummary? summary;
  final UsageBreakdown? breakdown;
  final UsageBreakdown? trend;
  /// 近 16 周按日用量（GitHub 风格热力图）。
  final UsageBreakdown? heatmap;
  final bool loading;
  final bool fromCache;
  final String? error;

  UsageSnapshot copyWith({
    UsageQueryState? query,
    UsageSummary? summary,
    UsageBreakdown? breakdown,
    UsageBreakdown? trend,
    UsageBreakdown? heatmap,
    bool? loading,
    bool? fromCache,
    String? error,
    bool clearError = false,
    bool clearData = false,
  }) {
    return UsageSnapshot(
      query: query ?? this.query,
      summary: clearData ? null : (summary ?? this.summary),
      breakdown: clearData ? null : (breakdown ?? this.breakdown),
      trend: clearData ? null : (trend ?? this.trend),
      heatmap: clearData ? null : (heatmap ?? this.heatmap),
      loading: loading ?? this.loading,
      fromCache: fromCache ?? this.fromCache,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class UsageRepository extends StateNotifier<UsageSnapshot> {
  UsageRepository(this._ref) : super(const UsageSnapshot());

  final Ref _ref;
  int _reqSeq = 0;

  AppSettings get _settings => _ref.read(settingsProvider);

  UsageDiskCache get _cache =>
      UsageDiskCache(_ref.read(sharedPrefsProvider));

  Future<void> setQuery(UsageQueryState query) async {
    state = state.copyWith(query: query);
    await refresh();
  }

  Future<void> refresh({bool forceNetwork = false}) async {
    final s = _settings;
    if (!s.isConfigured) {
      state = UsageSnapshot(query: state.query);
      return;
    }

    final seq = ++_reqSeq;
    final q = state.query;
    final (from, to) = q.window();
    final (trendFrom, trendTo) = q.trendWindow();
    final cacheKey = _cache.key(
      baseUrl: s.baseUrl.trim(),
      from: from.toUtc().toIso8601String(),
      to: to.toUtc().toIso8601String(),
      machineId: q.machineId,
      agent: q.agent,
      groupBy: '${q.groupBy}|${q.trendGroupBy}',
    );

    if (!forceNetwork && !s.demoMode) {
      final cached = _cache.read(cacheKey);
      if (cached != null) {
        state = state.copyWith(
          loading: !cached.isFresh,
          fromCache: true,
          summary: cached.summary,
          breakdown: cached.breakdown,
          trend: cached.trend,
          heatmap: cached.heatmap,
          clearError: true,
        );
        if (cached.isFresh) {
          // still revalidate in background lightly
        }
      } else {
        state = state.copyWith(loading: true, clearError: true);
      }
    } else {
      state = state.copyWith(loading: true, clearError: true);
    }

    if (s.demoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
      if (seq != _reqSeq) return;
      state = state.copyWith(
        loading: false,
        fromCache: false,
        summary: _demoSummary(from, to),
        breakdown: _demoBreakdown(from, to, q.groupBy),
        trend: _demoTrend(trendFrom, trendTo, byHour: q.trendByHour),
        heatmap: _demoHeatmap(),
        clearError: true,
      );
      return;
    }

    // If we already showed fresh cache, still refresh network once in background.
    final alreadyFresh = state.fromCache &&
        state.summary != null &&
        !forceNetwork &&
        (_cache.read(cacheKey)?.isFresh ?? false);

    if (alreadyFresh) {
      // soft revalidate without blocking UI spinner
      state = state.copyWith(loading: false);
    } else if (!state.fromCache) {
      state = state.copyWith(loading: true);
    }

    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final n = DateTime.now();
      final heatTo = n;
      final heatFrom = DateTime(n.year, n.month, n.day)
          .subtract(const Duration(days: 16 * 7 - 1));
      final results = await Future.wait([
        client.fetchUsageSummary(
          from: from,
          to: to,
          machineId: q.machineId,
          agent: q.agent,
        ),
        client.fetchUsageBreakdown(
          from: from,
          to: to,
          groupBy: q.groupBy,
          machineId: q.machineId,
          agent: q.agent,
        ),
        client.fetchUsageBreakdown(
          from: trendFrom,
          to: trendTo,
          groupBy: q.trendGroupBy,
          machineId: q.machineId,
          agent: q.agent,
        ),
        client.fetchUsageBreakdown(
          from: heatFrom,
          to: heatTo,
          groupBy: 'day',
          machineId: q.machineId,
          agent: q.agent,
        ),
      ]);
      if (seq != _reqSeq) return;
      final summary = results[0] as UsageSummary;
      final breakdown = results[1] as UsageBreakdown;
      final trend = results[2] as UsageBreakdown;
      final heatmap = results[3] as UsageBreakdown;
      state = state.copyWith(
        loading: false,
        fromCache: false,
        summary: summary,
        breakdown: breakdown,
        trend: trend,
        heatmap: heatmap,
        clearError: true,
      );
      await _cache.write(
        cacheKey,
        CachedUsage(
          savedAt: DateTime.now(),
          summary: summary,
          breakdown: breakdown,
          trend: trend,
          heatmap: heatmap,
        ),
      );
    } catch (e) {
      if (seq != _reqSeq) return;
      // keep cached data if any
      state = state.copyWith(
        loading: false,
        error: state.summary == null ? e.toString() : null,
      );
    }
  }
}

UsageSummary _demoSummary(DateTime from, DateTime to) {
  return UsageSummary(
    from: from,
    to: to,
    metrics: const UsageMetrics(
      inputTokens: 1821322,
      outputTokens: 223823,
      cacheHitTokens: 43426048,
      realUsage: 45471193,
      cacheHitRate: 0.9597,
      estimatedCostUsd: 12.34,
      eventCount: 368,
      priced: true,
    ),
  );
}

UsageBreakdown _demoBreakdown(DateTime from, DateTime to, String groupBy) {
  return UsageBreakdown(
    from: from,
    to: to,
    groupBy: groupBy,
    groups: const [
      UsageBreakdownGroup(
        key: 'claude-sonnet-4-5',
        metrics: UsageMetrics(
          inputTokens: 800000,
          outputTokens: 100000,
          cacheHitTokens: 30000000,
          realUsage: 30900000,
          eventCount: 200,
          estimatedCostUsd: 8.2,
          priced: true,
          cacheHitRate: 0.97,
        ),
      ),
      UsageBreakdownGroup(
        key: 'gpt-5.2',
        metrics: UsageMetrics(
          inputTokens: 1021322,
          outputTokens: 123823,
          reasoningTokens: 12000,
          cacheHitTokens: 13426048,
          realUsage: 14583193,
          eventCount: 168,
          estimatedCostUsd: 4.14,
          priced: true,
          cacheHitRate: 0.92,
        ),
      ),
    ],
  );
}

UsageBreakdown _demoTrend(DateTime from, DateTime to, {required bool byHour}) {
  final groups = <UsageBreakdownGroup>[];
  if (byHour) {
    final start = DateTime(from.year, from.month, from.day, from.hour);
    for (var i = 0; i < 24; i++) {
      final d = start.add(Duration(hours: i));
      if (d.isAfter(to)) break;
      final key =
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T${d.hour.toString().padLeft(2, '0')}';
      final v = 80000 + i * 12000 + (i.isEven ? 20000 : 0);
      groups.add(UsageBreakdownGroup(
        key: key,
        metrics: UsageMetrics(realUsage: v, inputTokens: v ~/ 2, eventCount: i + 1),
      ));
    }
    return UsageBreakdown(from: from, to: to, groupBy: 'hour', groups: groups);
  }
  for (var i = 6; i >= 0; i--) {
    final d = DateTime.now().subtract(Duration(days: i));
    final key =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final v = 2000000 + (6 - i) * 700000 + (i.isEven ? 400000 : 0);
    groups.add(UsageBreakdownGroup(
      key: key,
      metrics: UsageMetrics(realUsage: v, inputTokens: v ~/ 2, eventCount: 10 + i),
    ));
  }
  return UsageBreakdown(from: from, to: to, groupBy: 'day', groups: groups);
}


UsageBreakdown _demoHeatmap() {
  final n = DateTime.now();
  final end = DateTime(n.year, n.month, n.day);
  final start = end.subtract(const Duration(days: 16 * 7 - 1));
  final groups = <UsageBreakdownGroup>[];
  var day = start;
  var i = 0;
  while (!day.isAfter(end)) {
    final mid = DateTime(day.year, day.month, day.day, 12).toUtc();
    final key =
        '${mid.year.toString().padLeft(4, '0')}-${mid.month.toString().padLeft(2, '0')}-${mid.day.toString().padLeft(2, '0')}';
    final weekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final usage = weekend
        ? ((i % 9 == 0) ? 2500 : 0)
        : (6000 + (i * 173) % 45000);
    if (usage > 0) {
      groups.add(UsageBreakdownGroup(
        key: key,
        metrics: UsageMetrics(
          inputTokens: usage ~/ 2,
          outputTokens: usage ~/ 3,
          realUsage: usage,
          eventCount: usage ~/ 1500 + 1,
          priced: true,
          estimatedCostUsd: usage / 1e6 * 3,
        ),
      ));
    }
    day = day.add(const Duration(days: 1));
    i++;
  }
  return UsageBreakdown(
    from: start,
    to: end,
    groupBy: 'day',
    groups: groups,
  );
}

final usageRepositoryProvider =
    StateNotifierProvider<UsageRepository, UsageSnapshot>((ref) {
  final repo = UsageRepository(ref);
  Future.microtask(repo.refresh);
  ref.listen<List<Machine>>(
    statusRepositoryProvider.select((s) => s.machines),
    (_, __) {},
  );
  return repo;
});
