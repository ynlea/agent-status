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
    // 先算 diff 再更新快照，避免 prev/next 被写成同一拍导致漏通知。
    final prevSnapshot = previousSessions.isEmpty
        ? List<Session>.of(_lastAllSessions)
        : previousSessions;

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
      _lastAllSessions = all;
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
      unawaited(_syncWindowShape());
      return;
    }

    final announcements = IslandViewModel.diffAnnouncements(
      previous: prevSnapshot,
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

    _lastAllSessions = all;

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
    // 悬停不改 HWND，只改 UI，避免乱跳/错位
    unawaited(_syncWindowShape(allowHoverResize: false));
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
    // 展示满 10s 再切下一条（跑马灯同步该时长，不提前收）
    _collapseTimer = Timer(
      const Duration(seconds: kIslandAnnounceSeconds),
      onAnnouncementFinished,
    );
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
    // 仅改 phase；主窗 Overlay / 关窗岛形态都不要为 hover 改窗口尺寸
    state = state.copyWith(phase: IslandPhase.hover);
    _collapseTimer?.cancel();
  }

  void onHoverExit() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) {
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(phase: IslandPhase.strip, pinned: false);
  }

  void onTap() {
    if (!state.enabled || _playingAnnouncement) return;
    state = state.copyWith(
      phase: IslandPhase.card,
      pinned: true,
      clearAnnouncement: true,
    );
    _scheduleCollapse();
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

  bool _islandCardSized = false;

  Future<void> _syncWindowShape({bool allowHoverResize = false}) async {
    final wc = QingyaWindowController.instance;
    if (!wc.isReady || !isQingyaDesktop) return;
    // 主窗打开：不显示岛
    if (wc.mode == DesktopWindowMode.normal) {
      _islandCardSized = false;
      return;
    }

    if (!state.isVisible) {
      await wc.hideCompletely();
      _islandCardSized = false;
      return;
    }

    final wantCard = state.phase == IslandPhase.card ||
        state.hasAnnouncement ||
        state.pinned;

    if (wc.mode != DesktopWindowMode.island) {
      // 进入岛：先用小画布（strip/hover），避免大透明挡屏
      await wc.enterIslandMode(
        width: wantCard ? kIslandWindowCardWidth : kIslandWindowWidth,
        height: wantCard ? kIslandWindowCardHeight : kIslandWindowHeight,
      );
      _islandCardSized = wantCard;
      return;
    }

    // 已在岛形态：悬停绝不改尺寸；只在进入/离开卡片档时改一次
    if (wantCard && !_islandCardSized) {
      await wc.resizeIsland(
        width: kIslandWindowCardWidth,
        height: kIslandWindowCardHeight,
      );
      _islandCardSized = true;
    } else if (!wantCard && _islandCardSized) {
      await wc.resizeIsland(
        width: kIslandWindowWidth,
        height: kIslandWindowHeight,
      );
      _islandCardSized = false;
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
