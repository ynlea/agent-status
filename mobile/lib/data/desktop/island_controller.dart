import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../prefs/settings_store.dart';
import '../repo/status_repository.dart';
import 'desktop_platform.dart';
import 'island_models.dart';
import 'island_native_bridge.dart';

/// 主引擎岛状态：推送到原生置顶分层岛窗，动画在岛引擎内完成。
class IslandController extends StateNotifier<IslandViewModel> {
  IslandController(this._ref) : super(const IslandViewModel()) {
    if (!isQingyaDesktop) return;
    unawaited(IslandNativeBridge.instance.bind());
    unawaited(IslandNativeBridge.instance.ensure());

    _ref.listen<StatusSnapshot>(statusRepositoryProvider, (prev, next) {
      _recompute(
        previousSessions: prev?.sessions ?? _lastAllSessions,
        nudge: true,
      );
    });
    _ref.listen<AppSettings>(settingsProvider, (_, __) {
      _recompute(previousSessions: _lastAllSessions, nudge: false);
    });

    _subs.add(IslandNativeBridge.instance.announcementDone$.listen((_) {
      onAnnouncementFinished();
    }));

    _recompute(previousSessions: const [], nudge: false);
  }

  final Ref _ref;
  List<Session> _lastAllSessions = const [];
  final Queue<IslandAnnouncement> _announceQueue = Queue();
  Timer? _collapseTimer;
  bool _playingAnnouncement = false;
  final List<StreamSubscription<dynamic>> _subs = [];

  void _recompute({
    required List<Session> previousSessions,
    required bool nudge,
  }) {
    final settings = _ref.read(settingsProvider);
    final snapshot = _ref.read(statusRepositoryProvider);
    final enabled = settings.islandEnabled;
    final all = snapshot.sessions;
    _lastAllSessions = all;

    final filtered = IslandViewModel.filterSessions(
      activeSessions: snapshot.activeSessions,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );

    if (!enabled) {
      _collapseTimer?.cancel();
      _announceQueue.clear();
      _playingAnnouncement = false;
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
      unawaited(IslandNativeBridge.instance.sync(state));
      return;
    }

    final prevForDiff =
        previousSessions.isEmpty ? _lastAllSessions : previousSessions;
    final announcements = IslandViewModel.diffAnnouncements(
      previous: List.of(prevForDiff),
      next: all,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );

    if (nudge) {
      for (final a in announcements) {
        final exists = _announceQueue.any(
          (e) => e.sessionKey == a.sessionKey && e.state == a.state,
        );
        final samePlaying = state.announcement?.sessionKey == a.sessionKey &&
            state.announcement?.state == a.state;
        if (!exists && !samePlaying) _announceQueue.add(a);
      }
    }

    if (_playingAnnouncement || _announceQueue.isNotEmpty) {
      if (!_playingAnnouncement && _announceQueue.isNotEmpty) {
        _playNextAnnouncement(filtered, snapshot.connected);
        return;
      }
    }

    // 岛窗内本地处理 hover；主状态默认 strip，播报/钉住除外
    var phase = IslandPhase.strip;
    if (_playingAnnouncement && state.announcement != null) {
      phase = IslandPhase.card;
    } else if (state.pinned) {
      phase = IslandPhase.card;
    }

    state = IslandViewModel.fromSessions(
      filtered,
      phase: phase,
      pinned: state.pinned,
      enabled: true,
      announcement: state.announcement,
      connected: snapshot.connected,
    );
    unawaited(IslandNativeBridge.instance.sync(state));
  }

  void _playNextAnnouncement(List<Session> filtered, bool connected) {
    if (_announceQueue.isEmpty) {
      _playingAnnouncement = false;
      state = IslandViewModel.fromSessions(
        filtered,
        phase: IslandPhase.strip,
        pinned: false,
        enabled: true,
        connected: connected,
      );
      unawaited(IslandNativeBridge.instance.sync(state));
      return;
    }
    _playingAnnouncement = true;
    final ann = _announceQueue.removeFirst();
    state = IslandViewModel.fromSessions(
      filtered,
      phase: IslandPhase.card,
      pinned: false,
      enabled: true,
      announcement: ann,
      connected: connected,
    );
    unawaited(IslandNativeBridge.instance.sync(state));
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 12), onAnnouncementFinished);
  }

  void onAnnouncementFinished() {
    if (!state.enabled) return;
    final settings = _ref.read(settingsProvider);
    final snapshot = _ref.read(statusRepositoryProvider);
    final filtered = IslandViewModel.filterSessions(
      activeSessions: snapshot.activeSessions,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );
    if (_announceQueue.isNotEmpty) {
      _playNextAnnouncement(filtered, snapshot.connected);
      return;
    }
    _playingAnnouncement = false;
    state = IslandViewModel.fromSessions(
      filtered,
      phase: state.pinned ? IslandPhase.card : IslandPhase.strip,
      pinned: state.pinned,
      enabled: true,
      connected: snapshot.connected,
    );
    unawaited(IslandNativeBridge.instance.sync(state));
  }

  // 岛窗内本地 hover/tap；主侧保留接口供兼容。
  void onHoverEnter() {}
  void onHoverExit() {}
  void onTap() {
    if (!state.enabled || _playingAnnouncement) return;
    state = state.copyWith(
      phase: IslandPhase.card,
      pinned: true,
      clearAnnouncement: true,
    );
    unawaited(IslandNativeBridge.instance.sync(state));
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 10), () {
      if (state.pinned) collapse();
    });
  }

  void collapse() {
    _collapseTimer?.cancel();
    _playingAnnouncement = false;
    if (!state.enabled) {
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
    } else {
      state = IslandViewModel.fromSessions(
        state.sessions,
        phase: IslandPhase.strip,
        pinned: false,
        enabled: true,
        connected: state.connected,
      );
    }
    unawaited(IslandNativeBridge.instance.sync(state));
  }

  void expand() => onTap();

  Future<void> onMainCloseRequested() async {
    // 主窗隐藏；岛窗独立继续显示
    await IslandNativeBridge.instance.sync(state);
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}

final islandControllerProvider =
    StateNotifierProvider<IslandController, IslandViewModel>((ref) {
  return IslandController(ref);
});
