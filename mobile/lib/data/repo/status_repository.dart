import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../api/rest_client.dart';
import '../api/ws_client.dart';
import '../prefs/settings_store.dart';

class StatusSnapshot {
  const StatusSnapshot({
    this.machines = const [],
    this.sessions = const [],
    this.loading = false,
    this.error,
    this.connected = false,
  });

  final List<Machine> machines;
  final List<Session> sessions;
  final bool loading;
  final String? error;
  final bool connected;

  List<Session> get activeSessions => sortActiveSessions(
        sessions.map((s) {
          final m = machines.where((e) => e.machineId == s.machineId);
          return s.copyWith(
            machineName: m.isEmpty ? s.machineName : m.first.machineName,
          );
        }),
      );

  List<Session> sessionsFor(String machineId) {
    final list = sessions.where((s) => s.machineId == machineId).toList();
    list.sort((a, b) {
      final c = a.state.sortRank.compareTo(b.state.sortRank);
      if (c != 0) return c;
      return (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0));
    });
    return list;
  }

  StatusSnapshot copyWith({
    List<Machine>? machines,
    List<Session>? sessions,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? connected,
  }) {
    return StatusSnapshot(
      machines: machines ?? this.machines,
      sessions: sessions ?? this.sessions,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      connected: connected ?? this.connected,
    );
  }
}

class StatusRepository extends StateNotifier<StatusSnapshot> {
  StatusRepository(this._ref) : super(const StatusSnapshot()) {
    _ref.listen<AppSettings>(settingsProvider, (prev, next) {
      if (prev?.baseUrl != next.baseUrl ||
          prev?.apiKey != next.apiKey ||
          prev?.demoMode != next.demoMode) {
        unawaited(refresh());
      }
    });
    unawaited(refresh());
  }

  final Ref _ref;
  WsClient? _ws;
  Timer? _poll;

  AppSettings get _settings => _ref.read(settingsProvider);

  Future<void> refresh() async {
    final s = _settings;
    await _ws?.dispose();
    _ws = null;
    _poll?.cancel();

    if (!s.isConfigured) {
      state = const StatusSnapshot();
      return;
    }

    if (s.demoMode) {
      state = StatusSnapshot(
        machines: _demoMachines,
        sessions: _demoSessions,
        connected: true,
      );
      return;
    }

    state = state.copyWith(loading: true, clearError: true);
    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final machines = await client.fetchMachines();
      final sessions = <Session>[];
      for (final m in machines) {
        final list = await client.fetchSessions(m.machineId);
        sessions.addAll(
          list.map((e) => e.copyWith(machineName: m.machineName)),
        );
      }
      state = StatusSnapshot(
        machines: machines,
        sessions: sessions,
        connected: true,
      );
      _bindWs(s);
      _poll =
          Timer.periodic(const Duration(seconds: 20), (_) => _softRefresh());
    } catch (e) {
      final msg = e.toString();
      final friendly = msg.contains('SocketException') ||
              msg.contains('Failed host lookup') ||
              msg.contains('Network is unreachable')
          ? '无法访问服务器（网络/权限/域名）。请确认已装最新包，地址形如 https://agent.ynxx.buzz'
          : msg.contains('TimeoutException')
              ? '连接超时，请检查 Cloudflare 隧道与本机 29125 服务是否在线'
              : msg;
      state = state.copyWith(
        loading: false,
        connected: false,
        error: friendly,
      );
    }
  }

  Future<void> _softRefresh() async {
    final s = _settings;
    if (!s.isConfigured || s.demoMode) return;
    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final machines = await client.fetchMachines();
      final sessions = <Session>[];
      for (final m in machines) {
        final list = await client.fetchSessions(m.machineId);
        sessions.addAll(
          list.map((e) => e.copyWith(machineName: m.machineName)),
        );
      }
      state = state.copyWith(
        machines: machines,
        sessions: sessions,
        connected: true,
        clearError: true,
        loading: false,
      );
    } catch (_) {}
  }

  void _bindWs(AppSettings s) {
    final ws = WsClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
    _ws = ws;
    ws.onEvent = (type, payload) {
      if (type == 'session_upsert') {
        final session = Session.fromJson(payload);
        String? name = session.machineName;
        for (final m in state.machines) {
          if (m.machineId == session.machineId) {
            name = m.machineName;
            break;
          }
        }
        final next = session.copyWith(machineName: name);
        final list = [
          ...state.sessions.where((e) => !(e.machineId == next.machineId &&
              e.sessionId == next.sessionId &&
              e.agent == next.agent)),
          next,
        ];
        state = state.copyWith(sessions: list, connected: true);
      } else if (type == 'machine_online' || type == 'machine_offline') {
        final m = Machine.fromJson(payload);
        final machines = [
          ...state.machines.where((e) => e.machineId != m.machineId),
          m,
        ];
        state = state.copyWith(machines: machines, connected: true);
      } else if (type == 'notification') {
        // UI 层可选监听；此处标记已连接
        state = state.copyWith(connected: true);
      }
    };
    ws.connect();
  }

  @override
  void dispose() {
    _poll?.cancel();
    unawaited(_ws?.dispose() ?? Future.value());
    super.dispose();
  }
}

final statusRepositoryProvider =
    StateNotifierProvider<StatusRepository, StatusSnapshot>((ref) {
  return StatusRepository(ref);
});

// —— 演示数据：对齐原型文案气质 ——
const _demoMachines = [
  Machine(
    machineId: 'm-thinkbook',
    machineName: 'ThinkPad-X1',
    platform: 'linux',
    online: true,
    version: 'v0.1.4',
  ),
  Machine(
    machineId: 'm-macbook',
    machineName: 'MacBook-Pro',
    platform: 'darwin',
    online: true,
    version: 'v0.1.4',
  ),
  Machine(
    machineId: 'm-macmini',
    machineName: 'Mac mini',
    platform: 'darwin',
    online: true,
    version: 'v0.1.3',
  ),
  Machine(
    machineId: 'm-ubuntu',
    machineName: 'Ubuntu-Server',
    platform: 'linux',
    online: false,
    version: 'v0.1.2',
  ),
  Machine(
    machineId: 'm-windows',
    machineName: 'Windows-PC',
    platform: 'windows',
    online: false,
    version: 'v0.1.4',
  ),
];

final _demoSessions = [
  Session(
    machineId: 'm-thinkbook',
    agent: 'claude',
    sessionId: 's1',
    displayName: '/project/auth-service',
    state: SessionState.confirm,
    message: '优化登录逻辑，修复偶现问题',
    machineName: 'ThinkPad-X1',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
  ),
  Session(
    machineId: 'm-macbook',
    agent: 'codex',
    sessionId: 's2',
    displayName: '/project/file-center',
    state: SessionState.working,
    message: '实现文件上传接口',
    machineName: 'MacBook-Pro',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  ),
  Session(
    machineId: 'm-macmini',
    agent: 'claude',
    sessionId: 's3',
    displayName: '/docs/guide',
    state: SessionState.done,
    message: '更新文档说明',
    machineName: 'Mac mini',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
  ),
  Session(
    machineId: 'm-ubuntu',
    agent: 'codex',
    sessionId: 's4',
    displayName: '/project/analytics',
    state: SessionState.working,
    message: '重构数据统计模块',
    machineName: 'Ubuntu-Server',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
  ),
  Session(
    machineId: 'm-thinkbook',
    agent: 'claude',
    sessionId: 's5',
    displayName: '/docs/api',
    state: SessionState.idle,
    message: '整理接口文档',
    machineName: 'ThinkPad-X1',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
  ),
  Session(
    machineId: 'm-macbook',
    agent: 'opencode',
    sessionId: 's6',
    displayName: '/web/dashboard',
    state: SessionState.idle,
    message: '修复样式兼容问题',
    machineName: 'MacBook-Pro',
    updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
  ),
  Session(
    machineId: 'm-macmini',
    agent: 'codex',
    sessionId: 's7',
    displayName: '/project/core',
    state: SessionState.idle,
    message: '更新依赖包版本',
    machineName: 'Mac mini',
    updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
];
