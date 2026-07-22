import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../prefs/settings_store.dart';
import '../repo/status_repository.dart';
import 'desktop_platform.dart';
import 'island_models.dart';
import 'window_controller.dart';

/// 灵动岛状态机：细条 / 悬停 / 点击卡片；10s 无操作收起。
class IslandController extends StateNotifier<IslandViewModel> {
  IslandController(this._ref) : super(const IslandViewModel()) {
    if (!isQingyaDesktop) return;
    _ref.listen<StatusSnapshot>(statusRepositoryProvider, (_, __) {
      _recompute(nudge: true);
    });
    _ref.listen<AppSettings>(settingsProvider, (_, __) {
      _recompute(nudge: false);
    });
    _modeSub = WindowController.instance.modeStream.listen((_) {
      unawaited(_syncWindowToState());
    });
    _recompute(nudge: false);
  }

  final Ref _ref;
  List<Session> _prevFiltered = const [];
  Timer? _collapseTimer;
  bool _hovering = false;
  StreamSubscription<DesktopWindowMode>? _modeSub;

  void _recompute({required bool nudge}) {
    final settings = _ref.read(settingsProvider);
    final snapshot = _ref.read(statusRepositoryProvider);
    final enabled = settings.islandEnabled;
    final filtered = IslandViewModel.filterSessions(
      activeSessions: snapshot.activeSessions,
      notifyConfirm: settings.notifyConfirm,
      notifyWorking: settings.notifyWorking,
      notifyDone: settings.notifyDone,
    );

    if (!enabled) {
      _collapseTimer?.cancel();
      _hovering = false;
      _prevFiltered = filtered;
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
      unawaited(_syncWindowToState());
      return;
    }

    final shouldNudge = nudge &&
        IslandViewModel.shouldNudge(previous: _prevFiltered, next: filtered);
    _prevFiltered = filtered;

    var phase = state.phase;
    var pinned = state.pinned;

    if (phase == IslandPhase.hidden) {
      phase = IslandPhase.strip;
    }

    if (shouldNudge && filtered.isNotEmpty) {
      // 有新通知时轻推到悬停态（不强制钉住）
      if (phase == IslandPhase.strip) {
        phase = IslandPhase.hover;
        _scheduleCollapse();
      }
    }

    // 保持用户钉住 / 悬停
    if (pinned) {
      phase = IslandPhase.card;
    } else if (_hovering && phase != IslandPhase.card) {
      phase = IslandPhase.hover;
    } else if (phase != IslandPhase.hover && phase != IslandPhase.card) {
      phase = IslandPhase.strip;
    }

    state = IslandViewModel.fromSessions(
      filtered,
      phase: phase,
      pinned: pinned,
      enabled: true,
    );
    unawaited(_syncWindowToState());
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 10), () {
      if (!state.enabled) return;
      // 悬停中不收；钉住的卡片到期收起
      if (_hovering) {
        _scheduleCollapse();
        return;
      }
      if (state.phase == IslandPhase.card || state.phase == IslandPhase.hover) {
        state = state.copyWith(
          phase: IslandPhase.strip,
          pinned: false,
        );
        unawaited(_syncWindowToState());
      }
    });
  }

  void onHoverEnter() {
    if (!state.enabled) return;
    _hovering = true;
    if (state.pinned) return;
    state = state.copyWith(phase: IslandPhase.hover);
    _collapseTimer?.cancel();
    unawaited(_syncWindowToState());
  }

  void onHoverExit() {
    if (!state.enabled) return;
    _hovering = false;
    if (state.pinned) {
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(phase: IslandPhase.strip, pinned: false);
    unawaited(_syncWindowToState());
  }

  /// 点击：钉住展开卡片；再点细条外逻辑由 UI 处理打开会话。
  void onTap() {
    if (!state.enabled) return;
    if (state.phase == IslandPhase.card && state.pinned) {
      // 已展开：点击本体保持，刷新 10s 计时
      _scheduleCollapse();
      return;
    }
    state = state.copyWith(phase: IslandPhase.card, pinned: true);
    _scheduleCollapse();
    unawaited(_syncWindowToState());
  }

  void collapse() {
    _hovering = false;
    _collapseTimer?.cancel();
    if (!state.enabled) {
      state = const IslandViewModel(enabled: false, phase: IslandPhase.hidden);
    } else {
      state = state.copyWith(phase: IslandPhase.strip, pinned: false);
    }
    unawaited(_syncWindowToState());
  }

  /// 兼容旧调用。
  void expand() => onTap();

  Future<void> _syncWindowToState() async {
    final wc = WindowController.instance;
    if (!wc.isReady || !isQingyaDesktop) return;

    // 主窗正常时由 Overlay 绘制；仅后台模式改窗口形态。
    if (wc.mode == DesktopWindowMode.normal) return;

    if (!state.isVisible) {
      await wc.hideCompletely();
      return;
    }

    final size = _sizeFor(state.phase, state.hasSessions);
    if (wc.mode != DesktopWindowMode.island) {
      await wc.enterIslandMode(width: size.$1, height: size.$2);
    } else {
      await wc.resizeIsland(width: size.$1, height: size.$2);
    }
  }

  (double, double) _sizeFor(IslandPhase phase, bool hasSessions) {
    return switch (phase) {
      IslandPhase.hidden => (kIslandStripWidth, kIslandStripHeight),
      IslandPhase.strip => (kIslandStripWidth, kIslandStripHeight),
      IslandPhase.hover => (kIslandHoverWidth, kIslandHoverHeight),
      IslandPhase.card => (
          kIslandCardWidth,
          hasSessions ? kIslandCardHeightList : kIslandCardHeightEmpty,
        ),
    };
  }

  Future<void> onMainCloseRequested() async {
    final settings = _ref.read(settingsProvider);
    final preferIsland = settings.islandEnabled;
    await WindowController.instance.hideToBackground(
      preferIsland: preferIsland,
    );
    if (preferIsland) {
      unawaited(_syncWindowToState());
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
