import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/desktop/island_models.dart';
import 'domain/models.dart';
import 'theme/qingya_theme.dart';
import 'ui/desktop/island_bar.dart';

/// 原生岛窗入口：只跑灵动岛 UI，状态由主引擎经 C++ 桥同步。
@pragma('vm:entry-point')
void islandMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _IslandRoot());
}

class _IslandRoot extends StatefulWidget {
  const _IslandRoot();

  @override
  State<_IslandRoot> createState() => _IslandRootState();
}

class _IslandRootState extends State<_IslandRoot> {
  static const _view = MethodChannel('qingya/island_view');

  IslandViewModel _vm = const IslandViewModel(
    enabled: true,
    phase: IslandPhase.strip,
  );

  Timer? _enterDebounce;
  Timer? _exitDebounce;
  bool _pointerInside = false;

  @override
  void initState() {
    super.initState();
    _view.setMethodCallHandler((call) async {
      if (call.method == 'sync') {
        final raw = call.arguments;
        if (raw is String) {
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final next = IslandViewModel.fromJson(map);
          if (!mounted) return null;
          _applyRemote(next);
        }
      }
      return null;
    });
  }

  @override
  void dispose() {
    _enterDebounce?.cancel();
    _exitDebounce?.cancel();
    super.dispose();
  }

  void _applyRemote(IslandViewModel next) {
    if (!next.enabled || next.phase == IslandPhase.hidden) {
      setState(() => _vm = next);
      return;
    }
    var merged = next;
    // 保留本地悬停/钉住，避免主进程 strip 冲掉动画中间态
    if (next.hasAnnouncement) {
      merged = next;
    } else if (_vm.pinned) {
      merged = next.copyWith(phase: IslandPhase.card, pinned: true);
    } else if (_pointerInside && next.phase == IslandPhase.strip) {
      merged = next.copyWith(phase: IslandPhase.hover);
    }
    setState(() => _vm = merged);
  }

  void _onHoverEnter() {
    if (_vm.hasAnnouncement) return;
    _pointerInside = true;
    _exitDebounce?.cancel();
    _enterDebounce?.cancel();
    _enterDebounce = Timer(const Duration(milliseconds: 30), () {
      if (!mounted || !_pointerInside || _vm.pinned || _vm.hasAnnouncement) {
        return;
      }
      if (_vm.phase == IslandPhase.hover || _vm.phase == IslandPhase.card) {
        return;
      }
      setState(() => _vm = _vm.copyWith(phase: IslandPhase.hover));
    });
  }

  void _onHoverExit() {
    _pointerInside = false;
    _enterDebounce?.cancel();
    _exitDebounce?.cancel();
    _exitDebounce = Timer(const Duration(milliseconds: 140), () {
      if (!mounted || _pointerInside || _vm.pinned || _vm.hasAnnouncement) {
        return;
      }
      setState(() => _vm = _vm.copyWith(phase: IslandPhase.strip));
    });
  }

  void _onTap() {
    if (_vm.hasAnnouncement) return;
    _enterDebounce?.cancel();
    _exitDebounce?.cancel();
    setState(() {
      _vm = _vm.copyWith(
        phase: IslandPhase.card,
        pinned: true,
        clearAnnouncement: true,
      );
    });
  }

  void _onCollapse() {
    _enterDebounce?.cancel();
    _exitDebounce?.cancel();
    setState(() {
      _vm = _vm.copyWith(
        phase: _pointerInside ? IslandPhase.hover : IslandPhase.strip,
        pinned: false,
        clearAnnouncement: true,
      );
    });
  }

  Future<void> _openSession(Session s) async {
    await _view.invokeMethod('open_session', jsonEncode({
      'machineId': s.machineId,
      'agent': s.agent,
      'sessionId': s.sessionId,
    }));
    await _view.invokeMethod('show_main');
  }

  Future<void> _announcementDone() async {
    setState(() {
      _vm = _vm.copyWith(
        phase: _pointerInside ? IslandPhase.hover : IslandPhase.strip,
        pinned: false,
        clearAnnouncement: true,
      );
    });
    try {
      await _view.invokeMethod('announcement_done');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: QingyaTheme.light(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: ColoredBox(
          color: Colors.transparent,
          child: Align(
            alignment: Alignment.topCenter,
            child: !_vm.isVisible
                ? const SizedBox.shrink()
                : IslandSurface(
                    viewModel: _vm,
                    standalone: true,
                    onOpenSession: _openSession,
                    onHoverEnter: _onHoverEnter,
                    onHoverExit: _onHoverExit,
                    onTap: _onTap,
                    onCollapse: _onCollapse,
                    onAnnouncementFinished: _announcementDone,
                  ),
          ),
        ),
      ),
    );
  }
}
