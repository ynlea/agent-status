import '../../domain/models.dart';

/// 灵动岛展示形态。
enum IslandPhase {
  /// 功能关闭
  hidden,

  /// 贴顶细条
  strip,

  /// 鼠标悬停临时展开
  hover,

  /// 点击后常驻 / 通知播报卡片
  card,
}

/// 单次状态变更播报（用于跑马灯）。
class IslandAnnouncement {
  const IslandAnnouncement({
    required this.sessionKey,
    required this.title,
    required this.state,
    required this.line,
    this.agent = '',
    this.machineName = '',
  });

  final String sessionKey;
  final String title;
  final SessionState state;
  final String agent;
  final String machineName;

  /// 完整播报文案，例如：`优化登录逻辑 · Claude · 已完成`
  final String line;

  Map<String, dynamic> toJson() => {
        'sessionKey': sessionKey,
        'title': title,
        'state': state.name,
        'agent': agent,
        'machineName': machineName,
        'line': line,
      };

  factory IslandAnnouncement.fromJson(Map<String, dynamic> json) {
    return IslandAnnouncement(
      sessionKey: '${json['sessionKey'] ?? ''}',
      title: '${json['title'] ?? ''}',
      state: sessionStateFrom('${json['state']}'),
      agent: '${json['agent'] ?? ''}',
      machineName: '${json['machineName'] ?? ''}',
      line: '${json['line'] ?? ''}',
    );
  }
}

/// 从活跃会话 + 通知开关派生的岛视图模型。
class IslandViewModel {
  const IslandViewModel({
    this.sessions = const [],
    this.phase = IslandPhase.hidden,
    this.primary,
    this.badgeCount = 0,
    this.headline = '',
    this.subtitle = '',
    this.pinned = false,
    this.enabled = true,
    this.announcement,
    this.connected = false,
  });

  final List<Session> sessions;
  final IslandPhase phase;
  final Session? primary;
  final int badgeCount;
  final String headline;
  final String subtitle;
  final bool pinned;
  final bool enabled;
  final IslandAnnouncement? announcement;
  final bool connected;

  bool get isVisible => enabled && phase != IslandPhase.hidden;

  bool get hasSessions => sessions.isNotEmpty;

  bool get hasAnnouncement =>
      announcement != null && (announcement!.line).trim().isNotEmpty;

  IslandViewModel copyWith({
    List<Session>? sessions,
    IslandPhase? phase,
    Session? primary,
    int? badgeCount,
    String? headline,
    String? subtitle,
    bool? pinned,
    bool? enabled,
    IslandAnnouncement? announcement,
    bool? connected,
    bool clearPrimary = false,
    bool clearAnnouncement = false,
  }) {
    return IslandViewModel(
      sessions: sessions ?? this.sessions,
      phase: phase ?? this.phase,
      primary: clearPrimary ? null : (primary ?? this.primary),
      badgeCount: badgeCount ?? this.badgeCount,
      headline: headline ?? this.headline,
      subtitle: subtitle ?? this.subtitle,
      pinned: pinned ?? this.pinned,
      enabled: enabled ?? this.enabled,
      announcement:
          clearAnnouncement ? null : (announcement ?? this.announcement),
      connected: connected ?? this.connected,
    );
  }

  static List<Session> filterSessions({
    required List<Session> activeSessions,
    required bool notifyConfirm,
    required bool notifyWorking,
    required bool notifyDone,
  }) {
    final filtered = activeSessions.where((s) {
      return switch (s.state) {
        SessionState.confirm => notifyConfirm,
        SessionState.working => notifyWorking,
        SessionState.done => notifyDone,
        SessionState.idle => false,
      };
    });
    return sortActiveSessions(filtered);
  }

  static IslandViewModel fromSessions(
    List<Session> filtered, {
    IslandPhase phase = IslandPhase.strip,
    bool pinned = false,
    bool enabled = true,
    IslandAnnouncement? announcement,
    bool connected = false,
  }) {
    if (!enabled) {
      return const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
    }
    if (filtered.isEmpty) {
      return IslandViewModel(
        phase: phase,
        pinned: pinned,
        enabled: true,
        headline: '轻芽',
        subtitle: connected ? '暂无活跃会话' : '未连接',
        announcement: announcement,
        connected: connected,
      );
    }
    final primary = filtered.first;
    final n = filtered.length;
    final headline = n == 1
        ? primary.title
        : '${primary.state.labelZh} · 另有 ${n - 1} 个';
    final machine = primary.machineName?.trim();
    final subtitle = [
      if (machine != null && machine.isNotEmpty) machine,
      primary.agent,
      primary.state.labelZh,
    ].join(' · ');
    return IslandViewModel(
      sessions: filtered,
      phase: phase,
      primary: primary,
      badgeCount: n,
      headline: headline,
      subtitle: subtitle,
      pinned: pinned,
      enabled: true,
      announcement: announcement,
      connected: connected,
    );
  }

  static bool shouldNudge({
    required List<Session> previous,
    required List<Session> next,
  }) {
    if (next.isEmpty) return false;
    final prevKeys = {for (final s in previous) sessionKey(s): s.state};
    for (final s in next) {
      final k = sessionKey(s);
      final old = prevKeys[k];
      if (old == null) return true;
      if (s.state == SessionState.confirm && old != SessionState.confirm) {
        return true;
      }
      if (s.state.sortRank < old.sortRank) return true;
    }
    return false;
  }

  static bool shouldExpand({
    required List<Session> previous,
    required List<Session> next,
  }) =>
      shouldNudge(previous: previous, next: next);

  static String sessionKey(Session s) =>
      '${s.machineId}|${s.agent}|${s.sessionId}';

  /// 对比上一拍，生成「哪个会话、变成什么状态」的播报队列（优先 confirm/done）。
  static List<IslandAnnouncement> diffAnnouncements({
    required List<Session> previous,
    required List<Session> next,
    required bool notifyConfirm,
    required bool notifyWorking,
    required bool notifyDone,
  }) {
    bool allowed(SessionState st) => switch (st) {
          SessionState.confirm => notifyConfirm,
          SessionState.working => notifyWorking,
          SessionState.done => notifyDone,
          SessionState.idle => false,
        };

    final prevMap = {for (final s in previous) sessionKey(s): s};
    final out = <IslandAnnouncement>[];
    for (final s in next) {
      if (!allowed(s.state)) continue;
      final old = prevMap[sessionKey(s)];
      if (old == null || old.state != s.state) {
        final machine = s.machineName?.trim() ?? '';
        final line = [
          s.title,
          if (s.agent.isNotEmpty) s.agent,
          if (machine.isNotEmpty) machine,
          s.state.labelZh,
        ].join(' · ');
        out.add(
          IslandAnnouncement(
            sessionKey: sessionKey(s),
            title: s.title,
            state: s.state,
            agent: s.agent,
            machineName: machine,
            line: line,
          ),
        );
      }
    }
    // 高优在前
    out.sort((a, b) => a.state.sortRank.compareTo(b.state.sortRank));
    return out;
  }

  Map<String, dynamic> toJson() => {
        'phase': phase.name,
        'enabled': enabled,
        'pinned': pinned,
        'badgeCount': badgeCount,
        'headline': headline,
        'subtitle': subtitle,
        'connected': connected,
        'announcement': announcement?.toJson(),
        'sessions': [
          for (final s in sessions)
            {
              'machineId': s.machineId,
              'agent': s.agent,
              'sessionId': s.sessionId,
              'displayName': s.displayName,
              'message': s.message,
              'state': s.state.name,
              'machineName': s.machineName,
            },
        ],
        'primaryKey': primary == null ? null : sessionKey(primary!),
      };

  factory IslandViewModel.fromJson(Map<String, dynamic> json) {
    final phaseName = '${json['phase'] ?? 'strip'}';
    final phase = IslandPhase.values.firstWhere(
      (e) => e.name == phaseName,
      orElse: () => IslandPhase.strip,
    );
    final sessionsRaw = json['sessions'];
    final sessions = <Session>[];
    if (sessionsRaw is List) {
      for (final item in sessionsRaw) {
        if (item is! Map) continue;
        final m = item.cast<dynamic, dynamic>();
        sessions.add(
          Session(
            machineId: '${m['machineId'] ?? ''}',
            agent: '${m['agent'] ?? ''}',
            sessionId: '${m['sessionId'] ?? ''}',
            displayName: '${m['displayName'] ?? ''}',
            state: sessionStateFrom('${m['state']}'),
            message: '${m['message'] ?? ''}',
            machineName: m['machineName'] == null
                ? null
                : '${m['machineName']}',
          ),
        );
      }
    }
    IslandAnnouncement? ann;
    final annRaw = json['announcement'];
    if (annRaw is Map) {
      ann = IslandAnnouncement.fromJson(annRaw.cast<String, dynamic>());
    }
    Session? primary;
    final pk = json['primaryKey'];
    if (pk != null) {
      for (final s in sessions) {
        if (sessionKey(s) == '$pk') {
          primary = s;
          break;
        }
      }
    }
    primary ??= sessions.isEmpty ? null : sessions.first;
    return IslandViewModel(
      sessions: sessions,
      phase: phase,
      primary: primary,
      badgeCount: (json['badgeCount'] as num?)?.toInt() ?? sessions.length,
      headline: '${json['headline'] ?? ''}',
      subtitle: '${json['subtitle'] ?? ''}',
      pinned: json['pinned'] == true,
      enabled: json['enabled'] != false,
      announcement: ann,
      connected: json['connected'] == true,
    );
  }
}
