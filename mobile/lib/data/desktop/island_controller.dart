import 'dart:async';
import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../api/rest_client.dart';
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
      unawaited(_refreshTodayTokens());
    });
    _modeSub = QingyaWindowController.instance.modeStream.listen((_) {
      unawaited(_syncWindowShape());
    });
    _recompute(previousSessions: const [], nudge: false);
    unawaited(_refreshTodayTokens());
    _usageTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_refreshTodayTokens()),
    );
  }

  final Ref _ref;
  List<Session> _lastAllSessions = const [];
  final Queue<IslandAnnouncement> _announceQueue = Queue();
  Timer? _collapseTimer;
  Timer? _usageTimer;
  bool _hovering = false;
  bool _playingAnnouncement = false;
  /// 列表刚收起后强制停留在悬停胶囊，保证动画流畅。
  bool _dwellHover = false;
  int? _todayTokens;
  StreamSubscription<DesktopWindowMode>? _modeSub;

  (int, int, int?) _liveStats(StatusSnapshot snapshot) {
    final online = snapshot.machines.where((m) => m.online).length;
    final working =
        snapshot.sessions.where((s) => s.state == SessionState.working).length;
    // 今日用量优先；未拉到前用会话用量总和兜底
    final tokens = _todayTokens ??
        snapshot.sessions.fold<int>(
          0,
          (sum, s) => sum + (s.realUsage ?? 0),
        );
    return (online, working, tokens);
  }

  IslandViewModel _vmFrom(
    List<Session> filtered, {
    required IslandPhase phase,
    required bool pinned,
    required bool connected,
    IslandAnnouncement? announcement,
  }) {
    final snapshot = _ref.read(statusRepositoryProvider);
    final stats = _liveStats(snapshot);
    return IslandViewModel.fromSessions(
      filtered,
      phase: phase,
      pinned: pinned,
      enabled: true,
      announcement: announcement,
      connected: connected,
      onlineMachines: stats.$1,
      workingSessions: stats.$2,
      todayTokens: stats.$3,
    );
  }

  List<Session> _filteredNow() {
    final settings = _ref.read(settingsProvider);
    final snapshot = _ref.read(statusRepositoryProvider);
    return IslandViewModel.filterSessions(
      activeSessions: snapshot.activeSessions,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );
  }

  Future<void> _refreshTodayTokens() async {
    if (!isQingyaDesktop) return;
    final s = _ref.read(settingsProvider);
    if (!s.isConfigured || s.demoMode) return;
    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final summary = await client.fetchUsageSummary(from: from, to: now);
      final next = summary.metrics.realUsage;
      if (_todayTokens == next) return;
      _todayTokens = next;
      if (state.enabled) {
        _recompute(previousSessions: _lastAllSessions, nudge: false);
      }
    } catch (_) {
      // 忽略用量失败，悬停仍可用会话兜底
    }
  }

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
      _dwellHover = false;
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
    } else if (_hovering || _dwellHover) {
      phase = IslandPhase.hover;
    } else {
      phase = IslandPhase.strip;
    }

    state = _vmFrom(
      filtered,
      phase: phase,
      pinned: state.pinned,
      connected: snapshot.connected,
      announcement: state.announcement,
    );
    unawaited(_syncWindowShape());
  }

  void _playNextAnnouncement(List<Session> filtered, bool connected) {
    if (_announceQueue.isEmpty) {
      _playingAnnouncement = false;
      state = _vmFrom(
        filtered,
        phase: (_hovering || _dwellHover) ? IslandPhase.hover : IslandPhase.strip,
        pinned: false,
        connected: connected,
      );
      unawaited(_syncWindowShape());
      return;
    }
    _playingAnnouncement = true;
    final ann = _announceQueue.removeFirst();
    unawaited(() async {
      final wc = QingyaWindowController.instance;
      if (wc.isReady && wc.mode == DesktopWindowMode.island) {
        await wc.resizeIsland(
          width: kIslandWindowAnnounceWidth,
          height: kIslandWindowAnnounceHeight,
        );
        _appliedWinW = kIslandWindowAnnounceWidth;
        _appliedWinH = kIslandWindowAnnounceHeight;
      }
      if (!state.enabled) return;
      state = _vmFrom(
        filtered,
        phase: IslandPhase.card,
        pinned: false,
        connected: connected,
        announcement: ann,
      );
    }());
    _collapseTimer?.cancel();
    // 展示满 10s 再切下一条
    _collapseTimer = Timer(
      const Duration(seconds: kIslandAnnounceSeconds),
      onAnnouncementFinished,
    );
  }

  void onAnnouncementFinished() {
    if (!state.enabled) return;
    final snapshot = _ref.read(statusRepositoryProvider);
    final filtered = _filteredNow();
    if (_announceQueue.isNotEmpty) {
      _playNextAnnouncement(filtered, snapshot.connected);
      return;
    }
    _playingAnnouncement = false;
    // 通知结束后也走胶囊，再计时收条
    _collapseListToHover();
  }

  /// 列表展开时的自动收起：只收到胶囊，不直接收到细条。
  void _scheduleListCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 10), () {
      if (!state.enabled) return;
      if (_playingAnnouncement) return;
      if (state.pinned || state.phase == IslandPhase.card) {
        _collapseListToHover();
      }
    });
  }

  /// 胶囊 → 细条 的收起计时（列表收起后恢复）。
  void _scheduleHoverToStrip({
    Duration delay = const Duration(seconds: 3),
  }) {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(delay, () {
      if (!state.enabled) return;
      if (_hovering || _playingAnnouncement || state.pinned) return;
      if (state.phase != IslandPhase.hover && !_dwellHover) return;
      _goStrip(animateHwnd: true);
    });
  }

  /// 列表 / 通知 → 悬停胶囊，再恢复收条计时。
  void _collapseListToHover() {
    _collapseTimer?.cancel();
    _playingAnnouncement = false;
    _dwellHover = true;
    unawaited(_morphToHover());
    // 鼠标还在岛上：不自动收；否则 3s 后收到细条
    if (!_hovering) {
      _scheduleHoverToStrip();
    }
  }

  /// 先放大 HWND，再切 UI，内容展开不会被裁切。
  Future<void> _morphToHover() async {
    final wc = QingyaWindowController.instance;
    if (wc.isReady && wc.mode == DesktopWindowMode.island) {
      await wc.resizeIsland(
        width: kIslandWindowHoverWidth,
        height: kIslandWindowHoverHeight,
      );
      _appliedWinW = kIslandWindowHoverWidth;
      _appliedWinH = kIslandWindowHoverHeight;
    }
    if (!state.enabled || state.pinned) return;
    state = _vmFrom(
      _filteredNow(),
      phase: IslandPhase.hover,
      pinned: false,
      connected: state.connected,
    );
  }

  Future<void> _morphToCard() async {
    final wc = QingyaWindowController.instance;
    if (wc.isReady && wc.mode == DesktopWindowMode.island) {
      await wc.resizeIsland(
        width: kIslandWindowCardWidth,
        height: kIslandWindowCardHeight,
      );
      _appliedWinW = kIslandWindowCardWidth;
      _appliedWinH = kIslandWindowCardHeight;
    }
    if (!state.enabled) return;
    state = _vmFrom(
      _filteredNow(),
      phase: IslandPhase.card,
      pinned: true,
      connected: state.connected,
    );
  }

  void _goStrip({required bool animateHwnd}) {
    _dwellHover = false;
    state = _vmFrom(
      _filteredNow(),
      phase: IslandPhase.strip,
      pinned: false,
      connected: state.connected,
    );
    if (!animateHwnd) {
      unawaited(_syncWindowShape());
      return;
    }
    // 先让 UI 收成细条，再缩 HWND，避免动画中途被裁切
    Future<void>.delayed(
      const Duration(milliseconds: kIslandHwndShrinkDelayMs),
      () {
        if (!state.enabled) return;
        if (_hovering || _dwellHover || state.pinned || _playingAnnouncement) {
          return;
        }
        if (state.phase != IslandPhase.strip) return;
        unawaited(_syncWindowShape());
      },
    );
  }

  void onHoverEnter() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = true;
    _dwellHover = false;
    if (state.pinned) return;
    // 列表展开时不计悬停收条
    _collapseTimer?.cancel();
    unawaited(_morphToHover());
  }

  void onHoverExit() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) {
      // 列表开着：不收，只等列表计时
      return;
    }
    // 离开胶囊：短延迟收条（避免移出一点就抖）
    _dwellHover = true;
    _scheduleHoverToStrip(delay: const Duration(milliseconds: 450));
  }

  void onTap() {
    if (!state.enabled || _playingAnnouncement) return;
    _dwellHover = false;
    // 打开列表：暂停胶囊收条计时
    _collapseTimer?.cancel();
    unawaited(_morphToCard().then((_) => _scheduleListCollapse()));
  }

  void collapse() {
    if (!state.enabled) {
      _collapseTimer?.cancel();
      _hovering = false;
      _dwellHover = false;
      _playingAnnouncement = false;
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
      unawaited(_syncWindowShape());
      return;
    }
    // 从列表收起：先回胶囊再计时收条
    if (state.pinned ||
        (state.phase == IslandPhase.card && !state.hasAnnouncement)) {
      _collapseListToHover();
      return;
    }
    _collapseTimer?.cancel();
    _hovering = false;
    _playingAnnouncement = false;
    _goStrip(animateHwnd: true);
  }

  void expand() => onTap();

  Future<void> onMainCloseRequested() async {
    final settings = _ref.read(settingsProvider);
    // 开启灵动岛时：最小化/关闭都进岛（不只看当前 isVisible）
    final preferIsland = settings.islandEnabled;
    await QingyaWindowController.instance.hideToBackground(
      preferIsland: preferIsland,
    );
  }

  /// 当前已应用的岛 HWND 尺寸，避免重复 setBounds。
  double? _appliedWinW;
  double? _appliedWinH;

  (double, double) _targetWindowSize() {
    // 列表卡片（点击钉住）
    final listCard = state.pinned ||
        (state.phase == IslandPhase.card && !state.hasAnnouncement);
    if (listCard) {
      return (kIslandWindowCardWidth, kIslandWindowCardHeight);
    }
    // 通知播报：宽胶囊
    if (state.hasAnnouncement || _playingAnnouncement) {
      return (kIslandWindowAnnounceWidth, kIslandWindowAnnounceHeight);
    }
    // 悬停胶囊（含列表收起后的短暂停留）
    if (state.phase == IslandPhase.hover || _hovering || _dwellHover) {
      return (kIslandWindowHoverWidth, kIslandWindowHoverHeight);
    }
    // 细条：HWND 贴内容，不留透明挡点击区
    return (kIslandWindowStripWidth, kIslandWindowStripHeight);
  }

  Future<void> _syncWindowShape() async {
    final wc = QingyaWindowController.instance;
    if (!wc.isReady || !isQingyaDesktop) return;
    // 主窗打开：不显示岛
    if (wc.mode == DesktopWindowMode.normal) {
      _appliedWinW = null;
      _appliedWinH = null;
      return;
    }

    if (!state.isVisible) {
      await wc.hideCompletely();
      _appliedWinW = null;
      _appliedWinH = null;
      return;
    }

    final target = _targetWindowSize();
    final w = target.$1;
    final h = target.$2;

    if (wc.mode != DesktopWindowMode.island) {
      await wc.enterIslandMode(width: w, height: h);
      _appliedWinW = w;
      _appliedWinH = h;
      return;
    }

    if (_appliedWinW == w && _appliedWinH == h) return;
    await wc.resizeIsland(width: w, height: h);
    _appliedWinW = w;
    _appliedWinH = h;
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _usageTimer?.cancel();
    unawaited(_modeSub?.cancel() ?? Future.value());
    super.dispose();
  }
}

final islandControllerProvider =
    StateNotifierProvider<IslandController, IslandViewModel>((ref) {
  return IslandController(ref);
});
