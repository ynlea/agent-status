enum SessionState { confirm, working, done, idle }

SessionState sessionStateFrom(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'confirm':
      return SessionState.confirm;
    case 'working':
      return SessionState.working;
    case 'done':
      return SessionState.done;
    default:
      return SessionState.idle;
  }
}

extension SessionStateX on SessionState {
  String get apiValue => name;

  String get labelZh {
    switch (this) {
      case SessionState.confirm:
        return '需确认';
      case SessionState.working:
        return '工作中';
      case SessionState.done:
        return '已完成';
      case SessionState.idle:
        return '空闲';
    }
  }

  int get sortRank {
    switch (this) {
      case SessionState.confirm:
        return 0;
      case SessionState.working:
        return 1;
      case SessionState.done:
        return 2;
      case SessionState.idle:
        return 3;
    }
  }

  bool get isActive => this != SessionState.idle;
}

class Machine {
  const Machine({
    required this.machineId,
    required this.machineName,
    required this.platform,
    required this.online,
    this.lastSeenAt,
    this.version = '',
  });

  final String machineId;
  final String machineName;
  final String platform;
  final bool online;
  final DateTime? lastSeenAt;
  /// 监测端二进制版本（如 v0.1.4），服务端从上报里带回
  final String version;

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: '${json['machine_id'] ?? ''}',
      machineName: '${json['machine_name'] ?? json['machine_id'] ?? ''}',
      platform: '${json['platform'] ?? ''}',
      online: json['online'] == true,
      lastSeenAt: _parseTime(json['last_seen_at']),
      version: '${json['version'] ?? ''}'.trim(),
    );
  }

  Machine copyWith({
    bool? online,
    String? version,
    String? machineName,
  }) =>
      Machine(
        machineId: machineId,
        machineName: machineName ?? this.machineName,
        platform: platform,
        online: online ?? this.online,
        lastSeenAt: lastSeenAt,
        version: version ?? this.version,
      );
}

class Session {
  const Session({
    required this.machineId,
    required this.agent,
    required this.sessionId,
    required this.displayName,
    required this.state,
    required this.message,
    this.updatedAt,
    this.machineName,
    this.cwd = '',
    this.lastAssistantMessage = '',
    this.source = '',
  });

  final String machineId;
  final String agent;
  final String sessionId;
  final String displayName;
  final SessionState state;
  final String message;
  final DateTime? updatedAt;
  final String? machineName;
  /// 完整项目路径
  final String cwd;
  /// Agent 最后一条完整输出
  final String lastAssistantMessage;
  final String source;

  String get title {
    final m = message.trim();
    if (m.isNotEmpty) return m;
    return displayName;
  }

  String get projectPath {
    final full = cwd.trim();
    if (full.isNotEmpty) return full;
    return displayName;
  }

  String subtitle({String? machine}) {
    final parts = <String>[
      displayName,
      agent,
      if ((machine ?? machineName)?.isNotEmpty == true)
        (machine ?? machineName)!,
    ];
    return parts.where((e) => e.trim().isNotEmpty).join(' · ');
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      machineId: '${json['machine_id'] ?? ''}',
      agent: '${json['agent'] ?? 'unknown'}',
      sessionId: '${json['session_id'] ?? ''}',
      displayName: '${json['display_name'] ?? json['session_id'] ?? ''}',
      state: sessionStateFrom('${json['state'] ?? ''}'),
      message: '${json['message'] ?? ''}',
      updatedAt: _parseTime(json['updated_at']),
      machineName:
          json['machine_name'] == null ? null : '${json['machine_name']}',
      cwd: '${json['cwd'] ?? ''}'.trim(),
      lastAssistantMessage: '${json['last_assistant_message'] ?? ''}',
      source: '${json['source'] ?? ''}',
    );
  }

  Session copyWith({
    SessionState? state,
    String? message,
    String? machineName,
    String? cwd,
    String? lastAssistantMessage,
    String? source,
  }) {
    return Session(
      machineId: machineId,
      agent: agent,
      sessionId: sessionId,
      displayName: displayName,
      state: state ?? this.state,
      message: message ?? this.message,
      updatedAt: updatedAt,
      machineName: machineName ?? this.machineName,
      cwd: cwd ?? this.cwd,
      lastAssistantMessage: lastAssistantMessage ?? this.lastAssistantMessage,
      source: source ?? this.source,
    );
  }
}

/// 外观偏好（持久化为字符串 system/light/dark）。
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromStorage(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'light':
        return AppThemeMode.light;
      case 'dark':
        return AppThemeMode.dark;
      default:
        return AppThemeMode.system;
    }
  }

  String get storageValue => name;

  String get labelZh => switch (this) {
        AppThemeMode.system => '跟随系统',
        AppThemeMode.light => '浅色',
        AppThemeMode.dark => '深色',
      };
}

class AppSettings {
  const AppSettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.notifyConfirm = true,
    this.notifyWorking = true,
    this.notifyDone = true,
    this.demoMode = false,
    this.themeMode = AppThemeMode.system,
  });

  final String baseUrl;
  final String apiKey;
  final bool notifyConfirm;
  final bool notifyWorking;
  final bool notifyDone;
  final bool demoMode;
  final AppThemeMode themeMode;

  bool get isConfigured =>
      demoMode || (baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty);

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    bool? notifyConfirm,
    bool? notifyWorking,
    bool? notifyDone,
    bool? demoMode,
    AppThemeMode? themeMode,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      notifyConfirm: notifyConfirm ?? this.notifyConfirm,
      notifyWorking: notifyWorking ?? this.notifyWorking,
      notifyDone: notifyDone ?? this.notifyDone,
      demoMode: demoMode ?? this.demoMode,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

DateTime? _parseTime(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v');
}

class UsageMetrics {
  const UsageMetrics({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.reasoningTokens = 0,
    this.cacheWriteTokens = 0,
    this.cacheHitTokens = 0,
    this.realUsage = 0,
    this.cacheHitRate,
    this.estimatedCostUsd,
    this.eventCount = 0,
    this.priced = false,
  });

  final int inputTokens;
  final int outputTokens;
  final int reasoningTokens;
  final int cacheWriteTokens;
  final int cacheHitTokens;
  final int realUsage;
  final double? cacheHitRate;
  final double? estimatedCostUsd;
  final int eventCount;
  final bool priced;

  int get outputTotal => outputTokens + reasoningTokens;

  factory UsageMetrics.fromJson(Map<String, dynamic> json) {
    return UsageMetrics(
      inputTokens: _asInt(json['input_tokens']),
      outputTokens: _asInt(json['output_tokens']),
      reasoningTokens: _asInt(json['reasoning_tokens']),
      cacheWriteTokens: _asInt(json['cache_write_tokens']),
      cacheHitTokens: _asInt(json['cache_hit_tokens']),
      realUsage: _asInt(json['real_usage']),
      cacheHitRate: _asDouble(json['cache_hit_rate']),
      estimatedCostUsd: _asDouble(json['estimated_cost_usd']),
      eventCount: _asInt(json['event_count']),
      priced: json['priced'] == true,
    );
  }
}

class UsageSummary {
  const UsageSummary({
    required this.from,
    required this.to,
    required this.metrics,
  });

  final DateTime? from;
  final DateTime? to;
  final UsageMetrics metrics;

  factory UsageSummary.fromJson(Map<String, dynamic> json) {
    return UsageSummary(
      from: _parseTime(json['from']),
      to: _parseTime(json['to']),
      metrics: UsageMetrics.fromJson(json),
    );
  }
}

class UsageBreakdownGroup {
  const UsageBreakdownGroup({
    required this.key,
    required this.metrics,
  });

  final String key;
  final UsageMetrics metrics;

  factory UsageBreakdownGroup.fromJson(Map<String, dynamic> json) {
    return UsageBreakdownGroup(
      key: '${json['key'] ?? ''}',
      metrics: UsageMetrics.fromJson(json),
    );
  }
}

class UsageBreakdown {
  const UsageBreakdown({
    required this.from,
    required this.to,
    required this.groupBy,
    required this.groups,
  });

  final DateTime? from;
  final DateTime? to;
  final String groupBy;
  final List<UsageBreakdownGroup> groups;

  factory UsageBreakdown.fromJson(Map<String, dynamic> json) {
    final list =
        (json['groups'] as List? ?? const []).cast<Map<String, dynamic>>();
    return UsageBreakdown(
      from: _parseTime(json['from']),
      to: _parseTime(json['to']),
      groupBy: '${json['group_by'] ?? 'model'}',
      groups: list.map(UsageBreakdownGroup.fromJson).toList(),
    );
  }
}

int _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v') ?? 0;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('$v');
}


List<Session> sortActiveSessions(Iterable<Session> input) {
  final list = input.where((s) => s.state.isActive).toList();
  list.sort((a, b) {
    final c = a.state.sortRank.compareTo(b.state.sortRank);
    if (c != 0) return c;
    final at = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bt.compareTo(at);
  });
  return list;
}
