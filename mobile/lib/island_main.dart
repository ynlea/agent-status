import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/desktop/desktop_platform.dart';
import 'data/desktop/island_models.dart';
import 'domain/models.dart';
import 'theme/qingya_theme.dart';
import 'ui/desktop/island_bar.dart';

/// 原生岛窗入口：只跑灵动岛 UI。
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
  Timer? _sizeDebounce;
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
    // 首帧后按 strip 收紧窗口
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestNativeSize());
  }

  @override
  void dispose() {
    _enterDebounce?.cancel();
    _exitDebounce?.cancel();
    _sizeDebounce?.cancel();
    super.dispose();
  }

  void _applyRemote(IslandViewModel next) {
    if (!next.enabled || next.phase == IslandPhase.hidden) {
      setState(() => _vm = next);
      _requestNativeSize();
      return;
    }
    var merged = next;
    if (next.hasAnnouncement) {
      merged = next;
    } else if (_vm.pinned) {
      merged = next.copyWith(phase: IslandPhase.card, pinned: true);
    } else if (_pointerInside && next.phase == IslandPhase.strip) {
      merged = next.copyWith(phase: IslandPhase.hover);
    }
    setState(() => _vm = merged);
    _requestNativeSize();
  }

  (double, double) _sizeFor(IslandViewModel vm) {
    if (!vm.isVisible) return (120, 32);
    return switch (vm.phase) {
      IslandPhase.hidden => (120.0, 32.0),
      IslandPhase.strip => (kIslandStripWidth + 24, kIslandStripHitHeight + 8),
      IslandPhase.hover => (kIslandHoverWidth + 16, kIslandHoverHeight + 12),
      IslandPhase.card => (
          kIslandCardWidth + 16,
          (vm.hasAnnouncement
                  ? kIslandAnnounceHeight
                  : (vm.hasSessions
                      ? (vm.sessions.length == 1
                          ? 150.0
                          : kIslandCardHeightList)
                      : kIslandCardHeightEmpty)) +
              12,
        ),
    };
  }

  void _requestNativeSize() {
    _sizeDebounce?.cancel();
    _sizeDebounce = Timer(const Duration(milliseconds: 16), () async {
      final s = _sizeFor(_vm);
      try {
        await _view.invokeMethod('set_size', {
          'width': s.$1.round(),
          'height': s.$2.round(),
        });
      } catch (_) {}
    });
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
      _requestNativeSize();
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
      _requestNativeSize();
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
    _requestNativeSize();
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
    _requestNativeSize();
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
    _requestNativeSize();
    try {
      await _view.invokeMethod('announcement_done');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // 深色底：即便透明合成失败，也能看见岛区，而不是“隐形挡点击”。
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: QingyaTheme.light(),
      home: Scaffold(
        backgroundColor: const Color(0xFF1C1816),
        body: ColoredBox(
          color: const Color(0xFF1C1816),
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
