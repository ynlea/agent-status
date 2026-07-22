import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../../data/desktop/island_models.dart';
import '../../data/desktop/island_window_bridge.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import 'island_bar.dart';

/// 独立灵动岛子窗口入口 UI。
class IslandWindowApp extends StatefulWidget {
  const IslandWindowApp({super.key});

  @override
  State<IslandWindowApp> createState() => _IslandWindowAppState();
}

class _IslandWindowAppState extends State<IslandWindowApp> {
  IslandViewModel _vm = const IslandViewModel(phase: IslandPhase.strip);
  Timer? _hoverEnterDebounce;
  Timer? _hoverExitDebounce;
  bool _pointerInside = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bind());
  }

  @override
  void dispose() {
    _hoverEnterDebounce?.cancel();
    _hoverExitDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bind() async {
    final me = await WindowController.fromCurrentEngine();
    await me.setWindowMethodHandler((call) async {
      if (call.method == 'island_sync') {
        final raw = call.arguments;
        if (raw is String) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final vm = IslandViewModel.fromJson(map);
          if (!mounted) return null;
          _applyRemoteState(vm);
        }
        return null;
      }
      return null;
    });
  }

  void _applyRemoteState(IslandViewModel vm) {
    // 远程 sync 不打断本地悬停（除非播报/禁用）
    var next = vm;
    if (!vm.enabled || vm.phase == IslandPhase.hidden) {
      setState(() => _vm = vm);
      unawaited(IslandWindowHost.hideCanvas());
      return;
    }
    unawaited(IslandWindowHost.showCanvas());

    if (vm.hasAnnouncement) {
      setState(() => _vm = vm);
      return;
    }

    // 保留本地 hover / pinned，避免主进程 strip 把悬停冲掉
    if (_pointerInside && !vm.pinned && vm.phase == IslandPhase.strip) {
      next = vm.copyWith(phase: IslandPhase.hover);
    } else if (_vm.pinned && !vm.hasAnnouncement) {
      next = vm.copyWith(phase: IslandPhase.card, pinned: true);
    }
    setState(() => _vm = next);
  }

  void _onHoverEnter() {
    if (_vm.hasAnnouncement) return;
    _pointerInside = true;
    _hoverExitDebounce?.cancel();
    _hoverEnterDebounce?.cancel();
    // 短防抖：避免 HWND/合成器边缘抖动误触
    _hoverEnterDebounce = Timer(const Duration(milliseconds: 40), () {
      if (!mounted || !_pointerInside || _vm.hasAnnouncement) return;
      if (_vm.pinned) return;
      if (_vm.phase == IslandPhase.hover || _vm.phase == IslandPhase.card) {
        return;
      }
      setState(() => _vm = _vm.copyWith(phase: IslandPhase.hover));
    });
  }

  void _onHoverExit() {
    _pointerInside = false;
    _hoverEnterDebounce?.cancel();
    _hoverExitDebounce?.cancel();
    // 较长离手防抖：展开时指针滑到内容边缘不立刻收
    _hoverExitDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted || _pointerInside) return;
      if (_vm.hasAnnouncement || _vm.pinned) return;
      if (_vm.phase == IslandPhase.strip) return;
      setState(() => _vm = _vm.copyWith(phase: IslandPhase.strip));
    });
  }

  void _onTap() {
    if (_vm.hasAnnouncement) return;
    _hoverEnterDebounce?.cancel();
    _hoverExitDebounce?.cancel();
    setState(() {
      _vm = _vm.copyWith(
        phase: IslandPhase.card,
        pinned: true,
        clearAnnouncement: true,
      );
    });
  }

  void _onCollapse() {
    _hoverEnterDebounce?.cancel();
    _hoverExitDebounce?.cancel();
    setState(() {
      _vm = _vm.copyWith(
        phase: _pointerInside ? IslandPhase.hover : IslandPhase.strip,
        pinned: false,
        clearAnnouncement: true,
      );
    });
  }

  Future<void> _openSession(Session s) async {
    final payload = jsonEncode({
      'machineId': s.machineId,
      'agent': s.agent,
      'sessionId': s.sessionId,
    });
    final all = await WindowController.getAll();
    for (final w in all) {
      if (w.arguments != kIslandWindowArgument) {
        try {
          await w.invokeMethod('island_open_session', payload);
          await w.invokeMethod('island_show_main');
        } catch (_) {}
      }
    }
  }

  Future<void> _notifyMainAnnouncementDone() async {
    final next = _vm.copyWith(
      phase: _pointerInside ? IslandPhase.hover : IslandPhase.strip,
      pinned: false,
      clearAnnouncement: true,
    );
    setState(() => _vm = next);
    final all = await WindowController.getAll();
    for (final w in all) {
      if (w.arguments != kIslandWindowArgument) {
        try {
          await w.invokeMethod('island_announcement_done');
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: QingyaTheme.light(),
      darkTheme: QingyaTheme.dark(),
      themeMode: ThemeMode.light,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: ColoredBox(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: IslandSurface(
              viewModel: _vm,
              fillHost: false,
              standalone: true,
              onOpenSession: _openSession,
              onHoverEnter: _onHoverEnter,
              onHoverExit: _onHoverExit,
              onTap: _onTap,
              onCollapse: _onCollapse,
              onAnnouncementFinished: _notifyMainAnnouncementDone,
            ),
          ),
        ),
      ),
    );
  }
}
