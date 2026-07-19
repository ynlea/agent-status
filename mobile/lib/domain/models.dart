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
  });

  final String machineId;
  final String machineName;
  final String platform;
  final bool online;
  final DateTime? lastSeenAt;

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: '${json['machine_id'] ?? ''}',
      machineName: '${json['machine_name'] ?? json['machine_id'] ?? ''}',
      platform: '${json['platform'] ?? ''}',
      online: json['online'] == true,
      lastSeenAt: _parseTime(json['last_seen_at']),
    );
  }

  Machine copyWith({bool? online}) => Machine(
        machineId: machineId,
        machineName: machineName,
        platform: platform,
        online: online ?? this.online,
        lastSeenAt: lastSeenAt,
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
  });

  final String machineId;
  final String agent;
  final String sessionId;
  final String displayName;
  final SessionState state;
  final String message;
  final DateTime? updatedAt;
  final String? machineName;

  String get title {
    final m = message.trim();
    if (m.isNotEmpty) return m;
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
    );
  }

  Session copyWith({
    SessionState? state,
    String? message,
    String? machineName,
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
    );
  }
}

class AppSettings {
  const AppSettings({
    this.baseUrl = '',
    this.apiKey = '',
    this.notifyConfirm = true,
    this.notifyWorking = true,
    this.notifyDone = true,
    this.demoMode = false,
  });

  final String baseUrl;
  final String apiKey;
  final bool notifyConfirm;
  final bool notifyWorking;
  final bool notifyDone;
  final bool demoMode;

  bool get isConfigured =>
      demoMode || (baseUrl.trim().isNotEmpty && apiKey.trim().isNotEmpty);

  AppSettings copyWith({
    String? baseUrl,
    String? apiKey,
    bool? notifyConfirm,
    bool? notifyWorking,
    bool? notifyDone,
    bool? demoMode,
  }) {
    return AppSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      notifyConfirm: notifyConfirm ?? this.notifyConfirm,
      notifyWorking: notifyWorking ?? this.notifyWorking,
      notifyDone: notifyDone ?? this.notifyDone,
      demoMode: demoMode ?? this.demoMode,
    );
  }
}

DateTime? _parseTime(dynamic v) {
  if (v == null) return null;
  return DateTime.tryParse('$v');
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
