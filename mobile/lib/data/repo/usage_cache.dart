import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';

/// Disk cache for usage API payloads (per query fingerprint).
class UsageDiskCache {
  UsageDiskCache(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'usage_cache_v1:';
  static const ttl = Duration(minutes: 10);

  String key({
    required String baseUrl,
    required String from,
    required String to,
    String? machineId,
    String? agent,
    required String groupBy,
  }) {
    return '$_prefix$baseUrl|$machineId|$agent|$from|$to|$groupBy';
  }

  CachedUsage? read(String key) {
    final raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final savedAt = DateTime.tryParse('${map['saved_at']}');
      if (savedAt == null) return null;
      return CachedUsage(
        savedAt: savedAt,
        summary: UsageSummary.fromJson(
          (map['summary'] as Map).cast<String, dynamic>(),
        ),
        breakdown: UsageBreakdown.fromJson(
          (map['breakdown'] as Map).cast<String, dynamic>(),
        ),
        trend: UsageBreakdown.fromJson(
          (map['trend'] as Map).cast<String, dynamic>(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String key, CachedUsage data) async {
    final payload = {
      'saved_at': data.savedAt.toIso8601String(),
      'summary': _summaryJson(data.summary),
      'breakdown': _breakdownJson(data.breakdown),
      'trend': _breakdownJson(data.trend),
    };
    await _prefs.setString(key, jsonEncode(payload));
  }

  Map<String, dynamic> _summaryJson(UsageSummary s) => {
        'from': s.from?.toIso8601String(),
        'to': s.to?.toIso8601String(),
        ..._metricsJson(s.metrics),
      };

  Map<String, dynamic> _breakdownJson(UsageBreakdown b) => {
        'from': b.from?.toIso8601String(),
        'to': b.to?.toIso8601String(),
        'group_by': b.groupBy,
        'groups': b.groups
            .map((g) => {'key': g.key, ..._metricsJson(g.metrics)})
            .toList(),
      };

  Map<String, dynamic> _metricsJson(UsageMetrics m) => {
        'input_tokens': m.inputTokens,
        'output_tokens': m.outputTokens,
        'reasoning_tokens': m.reasoningTokens,
        'cache_write_tokens': m.cacheWriteTokens,
        'cache_hit_tokens': m.cacheHitTokens,
        'real_usage': m.realUsage,
        'cache_hit_rate': m.cacheHitRate,
        'estimated_cost_usd': m.estimatedCostUsd,
        'event_count': m.eventCount,
        'priced': m.priced,
      };
}

class CachedUsage {
  const CachedUsage({
    required this.savedAt,
    required this.summary,
    required this.breakdown,
    required this.trend,
  });

  final DateTime savedAt;
  final UsageSummary summary;
  final UsageBreakdown breakdown;
  final UsageBreakdown trend;

  bool get isFresh => DateTime.now().difference(savedAt) <= UsageDiskCache.ttl;
}
