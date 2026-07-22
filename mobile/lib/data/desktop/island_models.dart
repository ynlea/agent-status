import '../../domain/models.dart';

/// 灵动岛展示形态。
enum IslandPhase {
  /// 功能关闭
  hidden,

  /// 贴顶细条（默认收起）
  strip,

  /// 鼠标悬停临时展开
  hover,

  /// 点击后常驻卡片
  card,
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
  });

  final List<Session> sessions;
  final IslandPhase phase;
  final Session? primary;
  final int badgeCount;
  final String headline;
  final String subtitle;

  /// 是否由用户点击钉住展开。
  final bool pinned;

  /// 设置项：灵动岛总开关。
  final bool enabled;

  bool get isVisible => enabled && phase != IslandPhase.hidden;

  bool get hasSessions => sessions.isNotEmpty;

  String sessionRoute(Session s) =>
      '/sessions/${s.machineId}/${s.agent}/${Uri.encodeComponent(s.sessionId)}';

  IslandViewModel copyWith({
    List<Session>? sessions,
    IslandPhase? phase,
    Session? primary,
    int? badgeCount,
    String? headline,
    String? subtitle,
    bool? pinned,
    bool? enabled,
    bool clearPrimary = false,
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
    );
  }

  /// 过滤通知开关打开的 confirm/working/done，并按优先级排序。
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
  }) {
    if (!enabled) {
      return const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
    }
    if (filtered.isEmpty) {
      return IslandViewModel(
        phase: phase == IslandPhase.card || phase == IslandPhase.hover
            ? phase
            : IslandPhase.strip,
        pinned: pinned,
        enabled: true,
        headline: '轻芽',
        subtitle: '暂无活跃会话',
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
    );
  }

  /// 判断过滤结果是否相对上一拍「需要提示展开」（新增或状态升级到 confirm）。
  static bool shouldNudge({
    required List<Session> previous,
    required List<Session> next,
  }) {
    if (next.isEmpty) return false;
    final prevKeys = {
      for (final s in previous) _key(s): s.state,
    };
    for (final s in next) {
      final k = _key(s);
      final old = prevKeys[k];
      if (old == null) return true;
      if (s.state == SessionState.confirm && old != SessionState.confirm) {
        return true;
      }
      if (s.state.sortRank < old.sortRank) return true;
    }
    return false;
  }

  /// 兼容旧测试命名。
  static bool shouldExpand({
    required List<Session> previous,
    required List<Session> next,
  }) =>
      shouldNudge(previous: previous, next: next);

  static String _key(Session s) =>
      '${s.machineId}|${s.agent}|${s.sessionId}';
}
