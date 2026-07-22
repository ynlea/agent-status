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
    _modeSub = QingyaWindowController.instance.modeStream.listen((mode) {
      if (mode == DesktopWindowMode.normal) {
        // 主窗打开：丢掉排队播报，避免关窗后把积压既有状态一口气上岛
        _suppressAnnouncements(seedBaseline: true);
      }
      unawaited(_syncWindowShape());
      // 进岛后若仍有合法排队，确保 HWND 已是播报尺寸再播
      if (mode == DesktopWindowMode.island &&
          !_playingAnnouncement &&
          _announceQueue.isNotEmpty) {
        final snap = _ref.read(statusRepositoryProvider);
        _playNextAnnouncement(_filteredNow(), snap.connected);
      }
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
  /// 已建立会话基线后才做状态播报，避免首屏既有任务全量上岛。
  bool _hasSessionBaseline = false;
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

    // 首帧/冷启动：只记基线，不把既有会话当「新通知」
    if (!_hasSessionBaseline) {
      _lastAllSessions = List<Session>.of(all);
      _hasSessionBaseline = true;
      _announceQueue.clear();
      _playingAnnouncement = false;
    } else {
      final announcements = IslandViewModel.diffAnnouncements(
        previous: prevSnapshot,
        next: all,
        notifyConfirm: settings.notifyConfirm,
        notifyWorking: settings.notifyWorking,
        notifyDone: settings.notifyDone,
      );

      // 仅主窗隐藏（岛/托盘）时上岛播报；主窗打开时只更新基线
      final inBackground = QingyaWindowController.instance.isBackground;
      if (nudge && inBackground) {
        for (final a in announcements) {
          final exists = _announceQueue.any(
            (e) => e.sessionKey == a.sessionKey && e.state == a.state,
          );
          final samePlaying =
              state.announcement?.sessionKey == a.sessionKey &&
                  state.announcement?.state == a.state;
          if (!exists && !samePlaying) _announceQueue.add(a);
        }
      }

      _lastAllSessions = List<Session>.of(all);
    }

    if (_playingAnnouncement || _announceQueue.isNotEmpty) {
      if (!_playingAnnouncement &&
          _announceQueue.isNotEmpty &&
          QingyaWindowController.instance.isBackground) {
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
    // 主窗前台不播，避免关窗后才把积压通知挤扁显示
    if (!QingyaWindowController.instance.isBackground) {
      return;
    }
    _playingAnnouncement = true;
    final ann = _announceQueue.removeFirst();
    unawaited(() async {
      final wc = QingyaWindowController.instance;
      // 等进岛过渡结束，再拉到播报尺寸，避免细条 HWND 把胶囊压扁
      var wait = 0;
      while (wc.isReady &&
          wc.mode != DesktopWindowMode.island &&
          wait < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        wait++;
      }
      wait = 0;
      while (wc.isReady && wait < 20) {
        // enterIslandMode 的 _transitioning 会挡 resize，稍等
        try {
          await wc.resizeIsland(
            width: kIslandWindowAnnounceWidth,
            height: kIslandWindowAnnounceHeight,
          );
          _appliedWinW = kIslandWindowAnnounceWidth;
          _appliedWinH = kIslandWindowAnnounceHeight;
          break;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 30));
        wait++;
      }
      if (!state.enabled) return;
      state = _vmFrom(
        filtered,
        phase: IslandPhase.card,
        pinned: false,
        connected: connected,
        announcement: ann,
      );
      // 再同步一次，防止状态与 HWND 不一致
      unawaited(_syncWindowShape());
    }());
    _collapseTimer?.cancel();
    _collapseTimer = Timer(
      const Duration(seconds: kIslandAnnounceSeconds),
      onAnnouncementFinished,
    );
  }

  /// 丢掉播报队列；[seedBaseline] 时把当前会话记为基线。
  void _suppressAnnouncements({required bool seedBaseline}) {
    _collapseTimer?.cancel();
    _announceQueue.clear();
    _playingAnnouncement = false;
    // 清掉正在展示的播报内容，避免主窗↔岛切换时残留卡片态
    if (state.announcement != null || state.phase == IslandPhase.card) {
      if (state.enabled && !state.pinned) {
        state = _vmFrom(
          _filteredNow(),
          phase: IslandPhase.strip,
          pinned: false,
          connected: state.connected,
        );
      } else if (state.enabled) {
        state = state.copyWith(clearAnnouncement: true);
      }
    }
    if (seedBaseline) {
      final all = _ref.read(statusRepositoryProvider).sessions;
      _lastAllSessions = List<Session>.of(all);
      _hasSessionBaseline = true;
    }
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

  /// 列表 / 通知 → 悬停胶囊（在线摘要），再恢复收条计时。
  void _collapseListToHover() {
    _collapseTimer?.cancel();
    _playingAnnouncement = false;
    _dwellHover = true;
    // 先清 pinned，避免 _morphToHover 被旧 pin 挡住（列表收不起的根因）
    unawaited(_morphToHover(force: true));
    if (!_hovering) {
      _scheduleHoverToStrip();
    }
  }

  /// 先瞬时放大 HWND（锚点固定），再切 UI 做单段尺寸动画。
  Future<void> _morphToHover({bool force = false}) async {
    if (!state.enabled) return;
    if (!force && state.pinned) return;
    final wc = QingyaWindowController.instance;
    if (wc.isReady && wc.mode == DesktopWindowMode.island) {
      // 瞬时 setBounds，不 await 额外帧，减少「停一下再长」的卡断
      await wc.resizeIsland(
        width: kIslandWindowHoverWidth,
        height: kIslandWindowHoverHeight,
      );
      _appliedWinW = kIslandWindowHoverWidth;
      _appliedWinH = kIslandWindowHoverHeight;
    }
    if (!state.enabled) return;
    if (!force && state.pinned) return;
    // 同一帧内切 phase，AnimatedContainer 立刻开跑
    state = _vmFrom(
      _filteredNow(),
      phase: IslandPhase.hover,
      pinned: false,
      connected: state.connected,
    );
  }

  Future<void> _morphToCard() async {
    if (!state.enabled) return;
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

  /// 主窗再进岛：清掉展开/钉住/积压播报，避免既有任务全量上岛与错位。
  void _resetIslandPresentation() {
    _hovering = false;
    _dwellHover = false;
    _appliedWinW = null;
    _appliedWinH = null;
    // 关主窗瞬间：以当前会话为基线，不回放主窗期间的「假新状态」
    _suppressAnnouncements(seedBaseline: true);
    if (!state.enabled) return;
    state = _vmFrom(
      _filteredNow(),
      phase: IslandPhase.strip,
      pinned: false,
      connected: state.connected,
    );
  }

  void onHoverEnter() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = true;
    _dwellHover = false;
    if (state.pinned) return;
    _collapseTimer?.cancel();
    unawaited(_morphToHover());
  }

  void onHoverExit() {
    if (!state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) return;
    _dwellHover = true;
    _scheduleHoverToStrip(delay: const Duration(milliseconds: 450));
  }

  void onTap() {
    if (!state.enabled) return;
    // 通知播报中：点击 = 手动关闭当前通知
    if (_playingAnnouncement || state.hasAnnouncement) {
      _dismissAnnouncement();
      return;
    }
    if (state.pinned) {
      // 列表已开时再点空白区 → 收起回胶囊
      _collapseListToHover();
      return;
    }
    _dwellHover = false;
    _collapseTimer?.cancel();
    unawaited(_morphToCard().then((_) => _scheduleListCollapse()));
  }

  /// 手动关掉当前通知（并清空排队，避免连播）。
  void _dismissAnnouncement() {
    _collapseTimer?.cancel();
    _announceQueue.clear();
    _playingAnnouncement = false;
    _collapseListToHover();
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
    // 通知中点收起：等同关闭通知
    if (_playingAnnouncement || state.hasAnnouncement) {
      _dismissAnnouncement();
      return;
    }
    // 从列表收起：必须回「x 台在线 · …」胶囊
    if (state.pinned || state.phase == IslandPhase.card) {
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
    final preferIsland = settings.islandEnabled;
    // 从主窗进岛前复位，避免上次展开态导致错位
    if (preferIsland) {
      _resetIslandPresentation();
    }
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
