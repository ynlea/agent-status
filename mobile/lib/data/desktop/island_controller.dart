import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../prefs/settings_store.dart';
import '../repo/status_repository.dart';
import 'desktop_platform.dart';
import 'island_models.dart';
import 'island_window_bridge.dart';

/// 主进程灵动岛状态：推送到独立吸顶子窗；处理变更播报队列。
class IslandController extends StateNotifier<IslandViewModel> {
  IslandController(this._ref) : super(const IslandViewModel()) {
    if (!isQingyaDesktop) return;
    _ref.listen<StatusSnapshot>(statusRepositoryProvider, (prev, next) {
      _recompute(
        previousSessions: prev?.sessions ?? _lastAllSessions,
        nudge: true,
      );
    });
    _ref.listen<AppSettings>(settingsProvider, (_, __) {
      _recompute(previousSessions: _lastAllSessions, nudge: false);
    });
    unawaited(IslandWindowBridge.instance.ensureCreated());
    _recompute(previousSessions: const [], nudge: false);
  }

  final Ref _ref;
  List<Session> _lastAllSessions = const [];
  final Queue<IslandAnnouncement> _announceQueue = Queue();
  Timer? _collapseTimer;
  bool _hovering = false;
  bool _playingAnnouncement = false;

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
      _hovering = false;
      _announceQueue.clear();
      _playingAnnouncement = false;
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
      unawaited(IslandWindowBridge.instance.pushState(state));
      return;
    }

    // 用全量 sessions 做 diff，避免 done 被 active 列表挤掉时漏通知
    final prevForDiff = previousSessions.isEmpty ? _lastAllSessions : previousSessions;
    // 第一次只有当前拍时用 filtered 对比
    final announcements = IslandViewModel.diffAnnouncements(
      previous: _sessionsSnapshot(prevForDiff),
      next: all,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );

    // 仅在 nudge（状态源变化）时入队，避免设置改动重复播报
    if (nudge) {
      for (final a in announcements) {
        // 去重同 key+state
        final exists = _announceQueue.any(
          (e) => e.sessionKey == a.sessionKey && e.state == a.state,
        );
        if (!exists &&
            state.announcement?.sessionKey == a.sessionKey &&
            state.announcement?.state == a.state) {
          continue;
        }
        if (!exists) _announceQueue.add(a);
      }
    }

    var phase = state.phase;
    var pinned = state.pinned;
    if (phase == IslandPhase.hidden) phase = IslandPhase.strip;

    if (_playingAnnouncement || _announceQueue.isNotEmpty) {
      if (!_playingAnnouncement && _announceQueue.isNotEmpty) {
        _playNextAnnouncement(filtered, snapshot.connected);
        return;
      }
    } else {
      if (_hovering && !pinned) {
        phase = IslandPhase.hover;
      } else if (pinned) {
        phase = IslandPhase.card;
      } else {
        phase = IslandPhase.strip;
      }
    }

    state = IslandViewModel.fromSessions(
      filtered,
      phase: phase,
      pinned: pinned,
      enabled: true,
      announcement: state.announcement,
      connected: snapshot.connected,
    );
    unawaited(IslandWindowBridge.instance.pushState(state));
  }

  List<Session> _sessionsSnapshot(List<Session> list) => List.of(list);

  void _playNextAnnouncement(List<Session> filtered, bool connected) {
    if (_announceQueue.isEmpty) {
      _playingAnnouncement = false;
      state = IslandViewModel.fromSessions(
        filtered,
        phase: _hovering ? IslandPhase.hover : IslandPhase.strip,
        pinned: false,
        enabled: true,
        connected: connected,
      );
      unawaited(IslandWindowBridge.instance.pushState(state));
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
    unawaited(IslandWindowBridge.instance.pushState(state));
    // 跑马灯结束后由 UI 回调 onAnnouncementFinished；这里兜底 12s
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 12), () {
      onAnnouncementFinished();
    });
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
      phase: _hovering ? IslandPhase.hover : IslandPhase.strip,
      pinned: state.pinned,
      enabled: true,
      connected: snapshot.connected,
    );
    unawaited(IslandWindowBridge.instance.pushState(state));
    if (state.pinned) _scheduleCollapse();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 10), () {
      if (!state.enabled) return;
      if (_hovering || _playingAnnouncement) {
        _scheduleCollapse();
        return;
      }
      if (state.phase == IslandPhase.card || state.phase == IslandPhase.hover) {
        collapse();
      }
    });
  }

  void onHoverEnter() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = true;
    if (state.pinned) return;
    state = state.copyWith(phase: IslandPhase.hover);
    _collapseTimer?.cancel();
    unawaited(IslandWindowBridge.instance.pushState(state));
  }

  void onHoverExit() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) {
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(phase: IslandPhase.strip, pinned: false);
    unawaited(IslandWindowBridge.instance.pushState(state));
  }

  void onTap() {
    if (!state.enabled) return;
    if (_playingAnnouncement) return;
    if (state.phase == IslandPhase.card && state.pinned) {
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(
      phase: IslandPhase.card,
      pinned: true,
      clearAnnouncement: true,
    );
    _scheduleCollapse();
    unawaited(IslandWindowBridge.instance.pushState(state));
  }

  void collapse() {
    _hovering = false;
    _collapseTimer?.cancel();
    if (!state.enabled) {
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
    } else {
      final filtered = state.sessions;
      state = IslandViewModel.fromSessions(
        filtered,
        phase: IslandPhase.strip,
        pinned: false,
        enabled: true,
        connected: state.connected,
      );
    }
    _playingAnnouncement = false;
    unawaited(IslandWindowBridge.instance.pushState(state));
  }

  void expand() => onTap();

  Future<void> onMainCloseRequested() async {
    // 主窗只隐藏；岛是独立子窗，继续留在屏顶
    await IslandWindowBridge.instance.pushState(state);
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }
}

final islandControllerProvider =
    StateNotifierProvider<IslandController, IslandViewModel>((ref) {
  return IslandController(ref);
});
