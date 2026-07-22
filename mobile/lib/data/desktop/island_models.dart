import '../../domain/models.dart';

/// 灵动岛展示状态。
enum IslandPhase {
  /// 无目标会话：不显示
  hidden,

  /// 有会话：顶栏胶囊
  capsule,

  /// 变化后展开详情
  expanded,
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
  });

  final List<Session> sessions;
  final IslandPhase phase;
  final Session? primary;
  final int badgeCount;
  final String headline;
  final String subtitle;

  bool get isVisible => phase != IslandPhase.hidden && sessions.isNotEmpty;

  String sessionRoute(Session s) =>
      '/sessions/${s.machineId}/${s.agent}/${Uri.encodeComponent(s.sessionId)}';

  IslandViewModel copyWith({
    List<Session>? sessions,
    IslandPhase? phase,
    Session? primary,
    int? badgeCount,
    String? headline,
    String? subtitle,
  }) {
    return IslandViewModel(
      sessions: sessions ?? this.sessions,
      phase: phase ?? this.phase,
      primary: primary ?? this.primary,
      badgeCount: badgeCount ?? this.badgeCount,
      headline: headline ?? this.headline,
      subtitle: subtitle ?? this.subtitle,
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
    IslandPhase phase = IslandPhase.capsule,
  }) {
    if (filtered.isEmpty) {
      return const IslandViewModel();
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
    );
  }

  /// 判断过滤结果是否相对上一拍「需要展开」（新增或状态升级到 confirm）。
  static bool shouldExpand({
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

  static String _key(Session s) =>
      '${s.machineId}|${s.agent}|${s.sessionId}';
}
