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
      if (_disposed) return;
      _recompute(
        previousSessions: prev?.sessions ?? _lastAllSessions,
        nudge: true,
      );
    });
    _ref.listen<AppSettings>(settingsProvider, (_, __) {
      if (_disposed) return;
      _recompute(previousSessions: _lastAllSessions, nudge: false);
      unawaited(_refreshTodayTokens());
    });
    _modeSub = QingyaWindowController.instance.modeStream.listen((mode) {
      if (_disposed) return;
      if (mode == DesktopWindowMode.normal) {
        _islandEntryBlocked = false;
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

  /// 每次 morph 请求递增，旧 delayed shrink 看到过期值直接丢弃。
  int _morphGen = 0;

  /// 窗口形状请求版本。尺寸同步只提交最后一个版本的结果。
  int _shapeGen = 0;

  /// 所有窗口 API 调用共用一条尾部，保证 HWND 操作不并发。
  Future<void> _windowOpTail = Future<void>.value();
  Future<void>? _shapeSyncRunner;
  bool _shapeSyncPending = false;
  bool _islandEntryBlocked = false;
  bool _disposed = false;

  void _invalidateAsyncWork() {
    _morphGen++;
    _shapeGen++;
    _shapeSyncPending = false;
    _collapseTimer?.cancel();
  }

  bool _isMorphCurrent(int generation) {
    return !_disposed && generation == _morphGen && state.enabled;
  }

  bool _isShapeCurrent(int generation) {
    return !_disposed && generation == _shapeGen;
  }

  bool _isFormCurrent(int morphGeneration, int shapeGeneration) {
    return _isMorphCurrent(morphGeneration) && _isShapeCurrent(shapeGeneration);
  }

  /// 将窗口调用串行化，并在排队期间失效时跳过旧操作。
  Future<bool> _runWindowOperation(
    Future<void> Function() operation, {
    required bool Function() isCurrent,
  }) async {
    final previous = _windowOpTail;
    final release = Completer<void>();
    _windowOpTail = release.future;
    try {
      try {
        await previous;
      } catch (_) {
        // 前一个窗口调用失败不应阻塞后续最新请求。
      }
      if (_disposed || !isCurrent()) return false;
      await operation();
      return true;
    } catch (_) {
      // 单次失败由后续最新请求校正，同时避免 unawaited 异常外溢。
      return false;
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  (int, int, int?) _liveStats(StatusSnapshot snapshot) {
    final online = snapshot.machines.where((m) => m.online).length;
    // 只计 root，避免 Codex subagent 把 working 数抬高。
    final working = snapshot.sessions
        .where((s) => s.isRoot && s.state == SessionState.working)
        .length;
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
    if (_disposed || !isQingyaDesktop) return;
    final s = _ref.read(settingsProvider);
    if (!s.isConfigured || s.demoMode) return;
    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final summary = await client.fetchUsageSummary(from: from, to: now);
      if (_disposed) return;
      final next = summary.metrics.realUsage;
      if (_todayTokens == next) return;
      _todayTokens = next;
      if (!_disposed && state.enabled) {
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
    if (_disposed) return;
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
      _invalidateAsyncWork();
      _islandEntryBlocked = false;
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
          final samePlaying = state.announcement?.sessionKey == a.sessionKey &&
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
    if (_disposed || !state.enabled) return;
    if (_announceQueue.isEmpty) {
      _playingAnnouncement = false;
      unawaited(_morphToHover(force: true));
      return;
    }
    // 主窗前台不播，避免关窗后才把积压通知挤扁显示
    if (!QingyaWindowController.instance.isBackground) {
      return;
    }
    _playingAnnouncement = true;
    final ann = _announceQueue.removeFirst();
    _morphGen++; // 取消进行中的 morph
    _shapeGen++; // 播报尺寸优先于排队中的普通同步
    _shapeSyncPending = false;
    _collapseTimer?.cancel();
    final announcementGen = _morphGen;
    unawaited(() async {
      final wc = QingyaWindowController.instance;
      // 等进岛过渡结束，再拉到播报尺寸
      var wait = 0;
      while (wc.isReady && wc.mode != DesktopWindowMode.island && wait < 40) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        wait++;
      }
      if (!_isMorphCurrent(announcementGen) ||
          wc.mode != DesktopWindowMode.island) {
        return;
      }
      await _morphWindow(
        targetPhase: IslandPhase.card,
        targetPinned: false,
        targetWinW: kIslandWindowAnnounceWidth,
        targetWinH: kIslandWindowAnnounceHeight,
        announcement: ann,
      );
    }());
    _collapseTimer?.cancel();
    _collapseTimer = Timer(
      const Duration(seconds: kIslandAnnounceSeconds),
      onAnnouncementFinished,
    );
  }

  /// 丢掉播报队列；[seedBaseline] 时把当前会话记为基线。
  void _suppressAnnouncements({required bool seedBaseline}) {
    if (_disposed) return;
    _invalidateAsyncWork();
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
    if (_disposed || !state.enabled) return;
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
      if (_disposed || !state.enabled) return;
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
      if (_disposed || !state.enabled) return;
      if (_hovering || _playingAnnouncement || state.pinned) return;
      if (state.phase != IslandPhase.hover && !_dwellHover) return;
      _goStrip(animateHwnd: true);
    });
  }

  /// 列表 / 通知 → 悬停胶囊（在线摘要），再恢复收条计时。
  void _collapseListToHover() {
    if (_disposed || !state.enabled) return;
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
    if (_disposed || !state.enabled) return;
    if (!force && state.pinned) return;
    await _morphWindow(
      targetPhase: IslandPhase.hover,
      targetPinned: false,
      targetWinW: kIslandWindowHoverWidth,
      targetWinH: kIslandWindowHoverHeight,
    );
  }

  Future<void> _morphToCard() async {
    if (_disposed || !state.enabled) return;
    await _morphWindow(
      targetPhase: IslandPhase.card,
      targetPinned: true,
      targetWinW: kIslandWindowCardWidth,
      targetWinH: kIslandWindowCardHeight,
    );
  }

  /// 统一 morph：展开先 HWND 再 phase，收缩先 phase 再 HWND。
  Future<void> _morphWindow({
    required IslandPhase targetPhase,
    required bool targetPinned,
    required double targetWinW,
    required double targetWinH,
    bool clearAnnouncement = false,
    IslandAnnouncement? announcement,
  }) async {
    if (_disposed || !state.enabled) return;
    final gen = ++_morphGen;
    final shapeGen = ++_shapeGen;
    _shapeSyncPending = false;
    _collapseTimer?.cancel();
    final wc = QingyaWindowController.instance;

    final curArea = (_appliedWinW ?? 0) * (_appliedWinH ?? 0);
    final targetArea = targetWinW * targetWinH;
    final expanding = targetArea >= curArea;

    if (expanding) {
      // 先放大 HWND，再切 phase，避免裁切
      if (wc.isReady && wc.mode == DesktopWindowMode.island) {
        final applied = await _runWindowOperation(
          () => wc.resizeIsland(width: targetWinW, height: targetWinH),
          isCurrent: () =>
              _isFormCurrent(gen, shapeGen) &&
              wc.mode == DesktopWindowMode.island,
        );
        if (!_isFormCurrent(gen, shapeGen)) return;
        if (!applied || wc.mode != DesktopWindowMode.island) return;
        _appliedWinW = targetWinW;
        _appliedWinH = targetWinH;
      }
      if (!_isFormCurrent(gen, shapeGen)) return;
      state = _vmFrom(
        _filteredNow(),
        phase: targetPhase,
        pinned: targetPinned,
        connected: state.connected,
        announcement:
            clearAnnouncement ? null : (announcement ?? state.announcement),
      );
      if (wc.mode != DesktopWindowMode.island) {
        unawaited(_syncWindowShape());
      }
    } else {
      // 先切 phase（UI 开始缩小），动画结束后再收 HWND
      _dwellHover = targetPhase == IslandPhase.hover;
      if (!_isFormCurrent(gen, shapeGen)) return;
      state = _vmFrom(
        _filteredNow(),
        phase: targetPhase,
        pinned: targetPinned,
        connected: state.connected,
        announcement:
            clearAnnouncement ? null : (announcement ?? state.announcement),
      );
      // 用 UI 动画时长对齐，而非固定 magic delay
      final ms = targetPhase == IslandPhase.strip
          ? kIslandCollapseMs
          : kIslandCardCollapseMs;
      await Future<void>.delayed(Duration(milliseconds: ms));
      if (!_isFormCurrent(gen, shapeGen)) return;
      if (_hovering || state.pinned || _playingAnnouncement) return;
      if (wc.isReady && wc.mode == DesktopWindowMode.island) {
        final applied = await _runWindowOperation(
          () => wc.resizeIsland(width: targetWinW, height: targetWinH),
          isCurrent: () =>
              _isFormCurrent(gen, shapeGen) &&
              wc.mode == DesktopWindowMode.island,
        );
        if (!_isFormCurrent(gen, shapeGen)) return;
        if (!applied || wc.mode != DesktopWindowMode.island) return;
        _appliedWinW = targetWinW;
        _appliedWinH = targetWinH;
      } else {
        unawaited(_syncWindowShape());
      }
    }
  }

  void _goStrip({required bool animateHwnd}) {
    if (_disposed || !state.enabled) return;
    _dwellHover = false;
    _invalidateAsyncWork();
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
    // 动画时长与 UI 对齐后缩 HWND
    final gen = _morphGen;
    Future<void>.delayed(
      Duration(milliseconds: kIslandCollapseMs),
      () {
        if (!_isMorphCurrent(gen)) return;
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
    if (_disposed) return;
    _invalidateAsyncWork();
    _islandEntryBlocked = false;
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
    if (_disposed || !state.enabled || _playingAnnouncement) return;
    _hovering = true;
    _dwellHover = false;
    if (state.pinned) return;
    _collapseTimer?.cancel();
    unawaited(_morphToHover());
  }

  void onHoverExit() {
    if (_disposed || !state.enabled || _playingAnnouncement) return;
    _hovering = false;
    if (state.pinned) return;
    _dwellHover = true;
    _scheduleHoverToStrip(delay: const Duration(milliseconds: 450));
  }

  void onTap() {
    if (_disposed || !state.enabled) return;
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
    unawaited(_morphToCard().then((_) {
      if (!_disposed && state.enabled && state.pinned) {
        _scheduleListCollapse();
      }
    }));
  }

  /// 手动关掉当前通知（并清空排队，避免连播）。
  void _dismissAnnouncement() {
    if (_disposed) return;
    _collapseTimer?.cancel();
    _announceQueue.clear();
    _playingAnnouncement = false;
    _collapseListToHover();
  }

  void collapse() {
    if (_disposed) return;
    if (!state.enabled) {
      _invalidateAsyncWork();
      _islandEntryBlocked = false;
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
    if (_disposed) return;
    final settings = _ref.read(settingsProvider);
    final preferIsland = settings.islandEnabled;
    // 从主窗进岛前复位，避免上次展开态导致错位
    if (preferIsland) {
      _resetIslandPresentation();
    }
    await _runWindowOperation(
      () => QingyaWindowController.instance.hideToBackground(
        preferIsland: preferIsland,
      ),
      isCurrent: () => !_disposed,
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

  Future<void> _applyWindowShape(int request) async {
    if (!_isShapeCurrent(request) || !isQingyaDesktop) return;
    final wc = QingyaWindowController.instance;
    if (!wc.isReady) return;
    if (wc.mode == DesktopWindowMode.island) {
      _islandEntryBlocked = false;
    }

    // 主窗打开：不显示岛。
    if (wc.mode == DesktopWindowMode.normal) {
      if (_isShapeCurrent(request)) {
        _appliedWinW = null;
        _appliedWinH = null;
      }
      return;
    }

    if (!state.isVisible) {
      if (wc.mode != DesktopWindowMode.hidden) {
        final hidden = await _runWindowOperation(
          wc.hideCompletely,
          isCurrent: () => _isShapeCurrent(request),
        );
        if (!hidden || !_isShapeCurrent(request)) return;
      }
      if (_isShapeCurrent(request)) {
        _appliedWinW = null;
        _appliedWinH = null;
      }
      return;
    }

    final target = _targetWindowSize();
    final w = target.$1;
    final h = target.$2;
    bool targetStillCurrent() {
      return _isShapeCurrent(request) &&
          state.isVisible &&
          _targetWindowSize() == (w, h);
    }

    if (wc.mode != DesktopWindowMode.island) {
      if (_islandEntryBlocked) return;
      final entered = await _runWindowOperation(
        () => wc.enterIslandMode(width: w, height: h),
        isCurrent: targetStillCurrent,
      );
      if (!entered) return;
      if (wc.mode != DesktopWindowMode.island) {
        // 仅实际执行过进岛且最终落到 hidden 时视为失败。旧请求在排队中
        // 被新请求取消时不能误触发熔断，否则最新请求也无法进岛。
        if (wc.mode == DesktopWindowMode.hidden && state.isVisible) {
          _islandEntryBlocked = true;
        }
        // 进岛内部失败时停止自动重试，不写回已应用尺寸。
        if (!state.isVisible) {
          _appliedWinW = null;
          _appliedWinH = null;
        }
        return;
      }
      if (!targetStillCurrent()) return;
      _islandEntryBlocked = false;
      _appliedWinW = w;
      _appliedWinH = h;
      return;
    }

    if (_appliedWinW == w && _appliedWinH == h) return;
    final resized = await _runWindowOperation(
      () => wc.resizeIsland(width: w, height: h),
      isCurrent: () =>
          targetStillCurrent() && wc.mode == DesktopWindowMode.island,
    );
    if (!resized ||
        !targetStillCurrent() ||
        wc.mode != DesktopWindowMode.island) {
      return;
    }
    _appliedWinW = w;
    _appliedWinH = h;
  }

  /// 请求一次最新窗口形状；已有执行中的请求会在完成后重新取目标。
  Future<void> _syncWindowShape() {
    if (_disposed || !isQingyaDesktop) return Future<void>.value();
    _shapeGen++;
    _shapeSyncPending = true;
    final running = _shapeSyncRunner;
    if (running != null) return running;

    final runner = _drainWindowShape();
    _shapeSyncRunner = runner;
    return runner;
  }

  Future<void> _drainWindowShape() async {
    try {
      while (!_disposed && _shapeSyncPending) {
        _shapeSyncPending = false;
        final request = _shapeGen;
        await _applyWindowShape(request);
      }
    } finally {
      // 循环条件到释放执行器之间没有 await，不会漏掉新请求。
      _shapeSyncRunner = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidateAsyncWork();
    _announceQueue.clear();
    _playingAnnouncement = false;
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
