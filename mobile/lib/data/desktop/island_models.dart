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

/// 单次状态变更播报：分层信息，一眼看清机器/区段/项目/提示。
class IslandAnnouncement {
  const IslandAnnouncement({
    required this.sessionKey,
    required this.state,
    required this.machineName,
    required this.agentLabel,
    required this.projectLabel,
    required this.prompt,
    required this.line,
  });

  final String sessionKey;
  final SessionState state;

  /// 机器名，如 ThinkPad-X1
  final String machineName;

  /// 渠道/Agent，如 Claude / Codex
  final String agentLabel;

  /// 项目短名（路径末段或 displayName）
  final String projectLabel;

  /// 提示词/任务摘要（message 优先）
  final String prompt;

  /// 跑马灯整行备用文案
  final String line;

  Map<String, dynamic> toJson() => {
        'sessionKey': sessionKey,
        'state': state.name,
        'machineName': machineName,
        'agentLabel': agentLabel,
        'projectLabel': projectLabel,
        'prompt': prompt,
        'line': line,
      };

  factory IslandAnnouncement.fromJson(Map<String, dynamic> json) {
    return IslandAnnouncement(
      sessionKey: '${json['sessionKey'] ?? ''}',
      state: sessionStateFrom('${json['state']}'),
      machineName: '${json['machineName'] ?? ''}',
      agentLabel: '${json['agentLabel'] ?? json['agent'] ?? ''}',
      projectLabel: '${json['projectLabel'] ?? ''}',
      prompt: '${json['prompt'] ?? json['title'] ?? ''}',
      line: '${json['line'] ?? ''}',
    );
  }

  /// 从 Session 生成结构化播报。
  static IslandAnnouncement fromSession(Session s) {
    final machine = (s.machineName ?? '').trim();
    final agent = _agentLabel(s.agent);
    final project = _projectLabel(s);
    final prompt = _promptLabel(s);
    final line = [
      if (machine.isNotEmpty) machine,
      agent,
      if (project.isNotEmpty) project,
      if (prompt.isNotEmpty) prompt,
      s.state.labelZh,
    ].where((e) => e.trim().isNotEmpty).join(' · ');
    return IslandAnnouncement(
      sessionKey: IslandViewModel.sessionKey(s),
      state: s.state,
      machineName: machine.isEmpty ? '未知机器' : machine,
      agentLabel: agent,
      projectLabel: project.isEmpty ? '未知项目' : project,
      prompt: prompt.isEmpty ? '（无提示词）' : prompt,
      line: line,
    );
  }

  static String _agentLabel(String raw) {
    switch (raw.toLowerCase().trim()) {
      case 'claude':
        return 'Claude';
      case 'codex':
        return 'Codex';
      case 'opencode':
        return 'OpenCode';
      case '':
      case 'unknown':
        return '未知渠道';
      default:
        return raw;
    }
  }

  static String _projectLabel(Session s) {
    final cwd = s.cwd.trim();
    final source = cwd.isNotEmpty ? cwd : s.displayName.trim();
    if (source.isEmpty) return '';
    final norm = source.replaceAll('\\', '/');
    final parts = norm.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return source;
    // 取末 1～2 段，过长时仍可读
    if (parts.length >= 2 && parts.last.length < 4) {
      return '${parts[parts.length - 2]}/${parts.last}';
    }
    return parts.last;
  }

  static String _promptLabel(Session s) {
    final m = s.message.trim();
    if (m.isNotEmpty) return m;
    final d = s.displayName.trim();
    if (d.isNotEmpty && d != s.sessionId) return d;
    return '';
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
    final ann = IslandAnnouncement.fromSession(primary);
    final headline = n == 1
        ? ann.prompt
        : '${ann.state.labelZh} · 另有 ${n - 1} 个';
    final subtitle = [
      ann.machineName,
      ann.agentLabel,
      ann.projectLabel,
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
        out.add(IslandAnnouncement.fromSession(s));
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
