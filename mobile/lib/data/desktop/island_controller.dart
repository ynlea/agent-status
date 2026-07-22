import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../prefs/settings_store.dart';
import '../repo/status_repository.dart';
import 'desktop_platform.dart';
import 'island_models.dart';
import 'window_controller.dart';

/// 订阅状态与通知开关，驱动灵动岛显隐/展开，并与窗口模式联动。
class IslandController extends StateNotifier<IslandViewModel> {
  IslandController(this._ref) : super(const IslandViewModel()) {
    if (!isQingyaDesktop) return;
    _ref.listen<StatusSnapshot>(statusRepositoryProvider, (_, __) {
      _recompute(expandIfChanged: true);
    });
    _ref.listen<AppSettings>(settingsProvider, (_, __) {
      _recompute(expandIfChanged: false);
    });
    _modeSub = WindowController.instance.modeStream.listen((_) {
      _syncWindowToState();
    });
    _recompute(expandIfChanged: false);
  }

  final Ref _ref;
  List<Session> _prevFiltered = const [];
  Timer? _collapseTimer;
  StreamSubscription<DesktopWindowMode>? _modeSub;

  void _recompute({required bool expandIfChanged}) {
    final settings = _ref.read(settingsProvider);
    final snapshot = _ref.read(statusRepositoryProvider);
    final filtered = IslandViewModel.filterSessions(
      activeSessions: snapshot.activeSessions,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );

    var phase = IslandPhase.hidden;
    var newlyExpanded = false;
    if (filtered.isNotEmpty) {
      final expand = expandIfChanged &&
          IslandViewModel.shouldExpand(
            previous: _prevFiltered,
            next: filtered,
          );
      if (expand) {
        phase = IslandPhase.expanded;
        newlyExpanded = true;
      } else if (state.phase == IslandPhase.expanded && state.isVisible) {
        // 保持展开；勿在每次轮询/WS 刷新时重置收起计时
        phase = IslandPhase.expanded;
      } else {
        phase = IslandPhase.capsule;
      }
    } else {
      _collapseTimer?.cancel();
    }

    _prevFiltered = filtered;
    state = IslandViewModel.fromSessions(filtered, phase: phase);
    // 仅在新进入 expanded 时启动收起计时，避免 8s 轮询把岛一直钉在展开态
    if (newlyExpanded) {
      _scheduleCollapse(filtered);
    }
    unawaited(_syncWindowToState());
  }

  void _scheduleCollapse(List<Session> sessions) {
    _collapseTimer?.cancel();
    final hasConfirm =
        sessions.any((s) => s.state == SessionState.confirm);
    final duration =
        hasConfirm ? const Duration(seconds: 12) : const Duration(seconds: 6);
    _collapseTimer = Timer(duration, () {
      if (state.phase == IslandPhase.expanded && state.sessions.isNotEmpty) {
        state = state.copyWith(phase: IslandPhase.capsule);
        unawaited(_syncWindowToState());
      }
    });
  }

  /// 用户点击胶囊 → 展开。
  void expand() {
    if (state.sessions.isEmpty) return;
    state = state.copyWith(phase: IslandPhase.expanded);
    _scheduleCollapse(state.sessions);
    unawaited(_syncWindowToState());
  }

  void collapse() {
    if (state.sessions.isEmpty) {
      state = const IslandViewModel();
    } else {
      state = state.copyWith(phase: IslandPhase.capsule);
    }
    unawaited(_syncWindowToState());
  }

  Future<void> _syncWindowToState() async {
    final wc = WindowController.instance;
    if (!wc.isReady || !isQingyaDesktop) return;

    // 仅在后台（关主窗后）用主窗变形为岛；正常模式由 UI Overlay 绘制。
    if (wc.mode == DesktopWindowMode.normal) return;

    if (!state.isVisible) {
      await wc.hideCompletely();
      return;
    }

    final expanded = state.phase == IslandPhase.expanded;
    final w = expanded ? kIslandExpandedWidth : kIslandCapsuleWidth;
    final h = expanded ? kIslandExpandedHeight : kIslandCapsuleHeight;

    if (wc.mode != DesktopWindowMode.island) {
      await wc.enterIslandMode(width: w, height: h);
    } else {
      await wc.resizeIsland(width: w, height: h);
    }
  }

  /// 关主窗时：有岛内容则进入岛模式，否则隐藏。
  Future<void> onMainCloseRequested() async {
    final preferIsland = state.isVisible;
    await WindowController.instance.hideToBackground(
      preferIsland: preferIsland,
    );
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
