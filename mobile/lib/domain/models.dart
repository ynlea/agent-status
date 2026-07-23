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
    this.startedAt,
    this.realUsage,
    this.machineName,
    this.cwd = '',
    this.lastAssistantMessage = '',
    this.parentSessionId = '',
    this.source = '',
  });

  final String machineId;
  final String agent;
  final String sessionId;
  final String displayName;
  final SessionState state;
  final String message;
  final DateTime? updatedAt;
  /// 服务端首次入库时间；用于展示持续时长
  final DateTime? startedAt;
  /// 本会话真实用量（tokens）；null 表示服务端未下发
  final int? realUsage;
  final String? machineName;
  /// 完整项目路径
  final String cwd;
  /// Agent 最后一条完整输出
  final String lastAssistantMessage;
  /// Codex subagent 的主会话 id；空表示主会话
  final String parentSessionId;
  final String source;

  bool get isRoot => parentSessionId.trim().isEmpty;

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
      startedAt: _parseTime(json['started_at']),
      realUsage: json.containsKey('real_usage') ? _asInt(json['real_usage']) : null,
      machineName:
          json['machine_name'] == null ? null : '${json['machine_name']}',
      cwd: '${json['cwd'] ?? ''}'.trim(),
      lastAssistantMessage: '${json['last_assistant_message'] ?? ''}',
      parentSessionId: '${json['parent_session_id'] ?? ''}'.trim(),
      source: '${json['source'] ?? ''}',
    );
  }

  Session copyWith({
    SessionState? state,
    String? message,
    String? machineName,
    String? cwd,
    String? lastAssistantMessage,
    String? parentSessionId,
    String? source,
    DateTime? updatedAt,
    DateTime? startedAt,
    int? realUsage,
  }) {
    return Session(
      machineId: machineId,
      agent: agent,
      sessionId: sessionId,
      displayName: displayName,
      state: state ?? this.state,
      message: message ?? this.message,
      updatedAt: updatedAt ?? this.updatedAt,
      startedAt: startedAt ?? this.startedAt,
      realUsage: realUsage ?? this.realUsage,
      machineName: machineName ?? this.machineName,
      cwd: cwd ?? this.cwd,
      lastAssistantMessage: lastAssistantMessage ?? this.lastAssistantMessage,
      parentSessionId: parentSessionId ?? this.parentSessionId,
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
    this.islandEnabled = true,
  });

  final String baseUrl;
  final String apiKey;
  final bool notifyConfirm;
  final bool notifyWorking;
  final bool notifyDone;
  final bool demoMode;
  final AppThemeMode themeMode;

  /// Windows 灵动岛总开关。
  final bool islandEnabled;

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
    bool? islandEnabled,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      notifyConfirm: notifyConfirm ?? this.notifyConfirm,
      notifyWorking: notifyWorking ?? this.notifyWorking,
      notifyDone: notifyDone ?? this.notifyDone,
      demoMode: demoMode ?? this.demoMode,
      themeMode: themeMode ?? this.themeMode,
      islandEnabled: islandEnabled ?? this.islandEnabled,
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

/// Redacted cc-switch provider row from server snapshot.
class ProviderInfo {
  const ProviderInfo({
    required this.id,
    required this.name,
    this.baseUrl = '',
    this.model = '',
    this.modelAlias = '',
    this.anthropicModel = '',
    this.defaultHaikuModel = '',
    this.defaultSonnetModel = '',
    this.defaultOpusModel = '',
    this.category = '',
    this.hasApiKey = false,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String model;
  final String modelAlias;
  final String anthropicModel;
  final String defaultHaikuModel;
  final String defaultSonnetModel;
  final String defaultOpusModel;
  final String category;
  final bool hasApiKey;

  String modelSummary(String app) {
    if (app == 'codex') {
      return model.trim();
    }
    final parts = <String>[
      if (modelAlias.trim().isNotEmpty) modelAlias.trim(),
      if (anthropicModel.trim().isNotEmpty) anthropicModel.trim(),
    ];
    return parts.join(' · ');
  }

  factory ProviderInfo.fromJson(Map<String, dynamic> json) {
    return ProviderInfo(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      baseUrl: '${json['base_url'] ?? ''}',
      model: '${json['model'] ?? ''}',
      modelAlias: '${json['model_alias'] ?? ''}',
      anthropicModel: '${json['anthropic_model'] ?? ''}',
      defaultHaikuModel: '${json['default_haiku_model'] ?? ''}',
      defaultSonnetModel: '${json['default_sonnet_model'] ?? ''}',
      defaultOpusModel: '${json['default_opus_model'] ?? ''}',
      category: '${json['category'] ?? ''}',
      hasApiKey: json['has_api_key'] == true,
    );
  }
}

class ProviderAppSnapshot {
  const ProviderAppSnapshot({
    required this.app,
    this.currentId = '',
    this.providers = const [],
  });

  final String app;
  final String currentId;
  final List<ProviderInfo> providers;

  factory ProviderAppSnapshot.fromJson(Map<String, dynamic> json) {
    final list =
        (json['providers'] as List? ?? const []).cast<Map<String, dynamic>>();
    return ProviderAppSnapshot(
      app: '${json['app'] ?? ''}',
      currentId: '${json['current_id'] ?? ''}',
      providers: list.map(ProviderInfo.fromJson).toList(),
    );
  }
}

class ProvidersListResponse {
  const ProvidersListResponse({
    required this.machineId,
    this.apps = const [],
    this.updatedAt,
    this.ccSwitchAvailable = false,
    this.ccSwitchCliReady = false,
    this.ccSwitchBin = '',
  });

  final String machineId;
  final List<ProviderAppSnapshot> apps;
  final DateTime? updatedAt;
  final bool ccSwitchAvailable;
  final bool ccSwitchCliReady;
  final String ccSwitchBin;

  /// Can list/mutate provider rows in local DB (create/delete/duplicate/edit fields).
  bool get canManage => ccSwitchAvailable;

  /// Can switch / apply live config (needs CLI).
  bool get canApply => ccSwitchAvailable && ccSwitchCliReady;

  bool get ready => canApply;

  String get notReadyReason {
    if (!ccSwitchAvailable && !ccSwitchCliReady) {
      return '未安装或未检测到 cc-switch-cli / 本地数据库';
    }
    if (!ccSwitchCliReady) {
      return '未安装 cc-switch-cli（或监控端找不到可执行文件）';
    }
    if (!ccSwitchAvailable) {
      return '未找到本机 cc-switch 数据库（~/.cc-switch）';
    }
    return '';
  }

  String get manageBlockedReason {
    if (!ccSwitchAvailable) {
      return '未找到本机 cc-switch 数据库（~/.cc-switch）';
    }
    return '';
  }

  ProviderAppSnapshot? forApp(String app) {
    for (final a in apps) {
      if (a.app == app) return a;
    }
    return null;
  }

  factory ProvidersListResponse.fromJson(Map<String, dynamic> json) {
    final list = (json['apps'] as List? ?? const []).cast<Map<String, dynamic>>();
    return ProvidersListResponse(
      machineId: '${json['machine_id'] ?? ''}',
      apps: list.map(ProviderAppSnapshot.fromJson).toList(),
      updatedAt: _parseTime(json['updated_at']),
      ccSwitchAvailable: json['cc_switch_available'] == true,
      ccSwitchCliReady: json['cc_switch_cli_ready'] == true,
      ccSwitchBin: '${json['cc_switch_bin'] ?? ''}'.trim(),
    );
  }
}

class MachineCommand {
  const MachineCommand({
    required this.id,
    required this.machineId,
    required this.app,
    required this.type,
    required this.status,
    this.errorMessage = '',
  });

  final String id;
  final String machineId;
  final String app;
  final String type;
  final String status;
  final String errorMessage;

  bool get isTerminal =>
      status == 'succeeded' ||
      status == 'failed' ||
      status == 'timed_out' ||
      status == 'cancelled';

  bool get isSuccess => status == 'succeeded';

  factory MachineCommand.fromJson(Map<String, dynamic> json) {
    return MachineCommand(
      id: '${json['id'] ?? json['command_id'] ?? ''}',
      machineId: '${json['machine_id'] ?? ''}',
      app: '${json['app'] ?? ''}',
      type: '${json['type'] ?? ''}',
      status: '${json['status'] ?? ''}',
      errorMessage: '${json['error_message'] ?? ''}',
    );
  }
}
