import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../prefs/settings_store.dart';
import '../repo/status_repository.dart';
import 'desktop_platform.dart';
import 'island_models.dart';
import 'window_controller.dart';

/// 单窗灵动岛：主窗 Overlay；关主窗后主窗变形为屏顶岛。
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
    _modeSub = QingyaWindowController.instance.modeStream.listen((_) {
      unawaited(_syncWindowShape());
    });
    _recompute(previousSessions: const [], nudge: false);
  }

  final Ref _ref;
  List<Session> _lastAllSessions = const [];
  final Queue<IslandAnnouncement> _announceQueue = Queue();
  Timer? _collapseTimer;
  bool _hovering = false;
  bool _playingAnnouncement = false;
  StreamSubscription<DesktopWindowMode>? _modeSub;

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
      unawaited(_syncWindowShape());
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

    var phase = state.phase;
    if (phase == IslandPhase.hidden) phase = IslandPhase.strip;
    if (_playingAnnouncement && state.announcement != null) {
      phase = IslandPhase.card;
    } else if (state.pinned) {
      phase = IslandPhase.card;
    } else if (_hovering) {
      phase = IslandPhase.hover;
    } else {
      phase = IslandPhase.strip;
    }

    state = IslandViewModel.fromSessions(
      filtered,
      phase: phase,
      pinned: state.pinned,
      enabled: true,
      announcement: state.announcement,
      connected: snapshot.connected,
    );
    unawaited(_syncWindowShape());
  }

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
      unawaited(_syncWindowShape());
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
    unawaited(_syncWindowShape());
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
      phase: _hovering ? IslandPhase.hover : IslandPhase.strip,
      pinned: state.pinned,
      enabled: true,
      connected: snapshot.connected,
    );
    unawaited(_syncWindowShape());
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
    unawaited(_syncWindowShape());
  }

  void onHoverExit() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) {
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(phase: IslandPhase.strip, pinned: false);
    unawaited(_syncWindowShape());
  }

  void onTap() {
    if (!state.enabled || _playingAnnouncement) return;
    state = state.copyWith(
      phase: IslandPhase.card,
      pinned: true,
      clearAnnouncement: true,
    );
    _scheduleCollapse();
    unawaited(_syncWindowShape());
  }

  void collapse() {
    _hovering = false;
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
    unawaited(_syncWindowShape());
  }

  void expand() => onTap();

  Future<void> onMainCloseRequested() async {
    final settings = _ref.read(settingsProvider);
    final preferIsland = settings.islandEnabled && state.isVisible;
    await QingyaWindowController.instance.hideToBackground(
      preferIsland: preferIsland,
    );
  }

  (double, double) _islandWindowSize() {
    final vm = state;
    if (!vm.isVisible) return (kIslandStripWidth + 24, kIslandStripHitHeight + 12);
    return switch (vm.phase) {
      IslandPhase.hidden => (kIslandStripWidth + 24, kIslandStripHitHeight + 12),
      IslandPhase.strip => (kIslandStripWidth + 24, kIslandStripHitHeight + 12),
      IslandPhase.hover => (kIslandHoverWidth + 16, kIslandHoverHeight + 16),
      IslandPhase.card => (
          kIslandCardWidth + 16,
          (vm.hasAnnouncement
                  ? kIslandAnnounceHeight
                  : (vm.hasSessions
                      ? (vm.sessions.length == 1 ? 150.0 : kIslandCardHeightList)
                      : kIslandCardHeightEmpty)) +
              16,
        ),
    };
  }

  Future<void> _syncWindowShape() async {
    final wc = QingyaWindowController.instance;
    if (!wc.isReady || !isQingyaDesktop) return;
    if (wc.mode == DesktopWindowMode.normal) return;

    if (!state.isVisible) {
      await wc.hideCompletely();
      return;
    }
    final size = _islandWindowSize();
    if (wc.mode != DesktopWindowMode.island) {
      await wc.enterIslandMode(width: size.$1, height: size.$2);
    } else {
      await wc.resizeIsland(width: size.$1, height: size.$2);
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    unawaited(_modeSub?.cancel() ?? Future.value());
    super.dispose();
  }
}

final islandControllerProvider =
    StateNotifierProvider<IslandController, IslandViewModel>((ref) {
  return IslandController(ref);
});
