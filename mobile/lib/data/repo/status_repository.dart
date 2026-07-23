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
        sessions.where((s) => s.isRoot).map((s) {
          final m = machines.where((e) => e.machineId == s.machineId);
          return s.copyWith(
            machineName: m.isEmpty ? s.machineName : m.first.machineName,
          );
        }),
      );

  List<Session> sessionsFor(String machineId) {
    final list = sessions.where((s) => s.machineId == machineId && s.isRoot).toList();
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
      // 并行拉会话，降低多设备时的刷新延迟
      final sessionLists = await Future.wait(
        machines.map((m) async {
          final list = await client.fetchSessions(m.machineId);
          return list
              .map((e) => e.copyWith(machineName: m.machineName))
              .toList();
        }),
      );
      final sessions = <Session>[
        for (final list in sessionLists) ...list,
      ];
      state = StatusSnapshot(
        machines: machines,
        sessions: sessions,
        connected: true,
      );
      _bindWs(s);
      // WS 为主；轮询兜底再缩短一点
      _poll =
          Timer.periodic(const Duration(seconds: 5), (_) => softRefresh());
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

  Future<void> renameMachine(String machineId, String name) async {
    final s = _settings;
    name = name.trim();
    if (name.isEmpty) {
      throw Exception('名称不能为空');
    }
    if (s.demoMode) {
      final machines = [
        for (final m in state.machines)
          if (m.machineId == machineId) m.copyWith(machineName: name) else m,
      ];
      final sessions = [
        for (final sess in state.sessions)
          if (sess.machineId == machineId)
            sess.copyWith(machineName: name)
          else
            sess,
      ];
      state = state.copyWith(machines: machines, sessions: sessions);
      return;
    }
    if (!s.isConfigured) {
      throw Exception('未配置服务器');
    }
    final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
    final updated = await client.renameMachine(machineId, name);
    final machines = [
      for (final m in state.machines)
        if (m.machineId == machineId) updated else m,
    ];
    final sessions = [
      for (final sess in state.sessions)
        if (sess.machineId == machineId)
          sess.copyWith(machineName: updated.machineName)
        else
          sess,
    ];
    state = state.copyWith(machines: machines, sessions: sessions);
  }

  /// 轻量全量刷新（不打断 WS）。供轮询与回前台调用。
  Future<void> softRefresh() async {
    final s = _settings;
    if (!s.isConfigured || s.demoMode) return;
    try {
      final client = RestClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
      final machines = await client.fetchMachines();
      final sessionLists = await Future.wait(
        machines.map((m) async {
          final list = await client.fetchSessions(m.machineId);
          return list
              .map((e) => e.copyWith(machineName: m.machineName))
              .toList();
        }),
      );
      final sessions = <Session>[
        for (final list in sessionLists) ...list,
      ];
      state = state.copyWith(
        machines: machines,
        sessions: sessions,
        connected: true,
        clearError: true,
        loading: false,
      );
    } catch (_) {}
  }

  void _upsertSession(Session session) {
    String? name = session.machineName;
    for (final m in state.machines) {
      if (m.machineId == session.machineId) {
        name = m.machineName;
        break;
      }
    }
    final next = session.copyWith(machineName: name);
    final list = [
      ...state.sessions.where(
        (e) => !(e.machineId == next.machineId &&
            e.sessionId == next.sessionId &&
            e.agent == next.agent),
      ),
      next,
    ];
    state = state.copyWith(sessions: list, connected: true);
  }

  void _bindWs(AppSettings s) {
    final ws = WsClient(baseUrl: s.baseUrl, apiKey: s.apiKey);
    _ws = ws;
    ws.onEvent = (type, payload) {
      if (type == 'session_upsert') {
        _upsertSession(Session.fromJson(payload));
      } else if (type == 'session_remove') {
        final machineId = '${payload['machine_id'] ?? ''}';
        final sessionId = '${payload['session_id'] ?? ''}';
        final agent = '${payload['agent'] ?? ''}';
        final list = state.sessions
            .where(
              (e) => !(e.machineId == machineId &&
                  e.sessionId == sessionId &&
                  (agent.isEmpty || e.agent == agent)),
            )
            .toList();
        state = state.copyWith(sessions: list, connected: true);
      } else if (type == 'machine_online' || type == 'machine_offline') {
        final m = Machine.fromJson(payload);
        final machines = [
          ...state.machines.where((e) => e.machineId != m.machineId),
          m,
        ];
        state = state.copyWith(machines: machines, connected: true);
      } else if (type == 'notification') {
        // 状态推送也写进列表，避免只靠 20s 轮询才看到变化。
        // 必须保留 parent / cwd 等字段，否则会把 subagent 冲成“假主会话”。
        final machineId = '${payload['machine_id'] ?? ''}';
        final sessionId = '${payload['session_id'] ?? ''}';
        final agent = '${payload['agent'] ?? 'unknown'}';
        if (machineId.isNotEmpty && sessionId.isNotEmpty) {
          DateTime? at;
          final rawAt = payload['at'];
          if (rawAt is String && rawAt.isNotEmpty) {
            at = DateTime.tryParse(rawAt);
          }
          Session? existing;
          for (final e in state.sessions) {
            if (e.machineId == machineId &&
                e.sessionId == sessionId &&
                e.agent == agent) {
              existing = e;
              break;
            }
          }
          final parentFromPayload =
              '${payload['parent_session_id'] ?? ''}'.trim();
          final displayFromPayload = '${payload['display_name'] ?? ''}'.trim();
          _upsertSession(
            Session(
              machineId: machineId,
              agent: agent,
              sessionId: sessionId,
              displayName: displayFromPayload.isNotEmpty
                  ? displayFromPayload
                  : (existing?.displayName.isNotEmpty == true
                      ? existing!.displayName
                      : sessionId),
              state: sessionStateFrom('${payload['state'] ?? ''}'),
              message: '${payload['message'] ?? ''}',
              updatedAt: at ?? existing?.updatedAt ?? DateTime.now(),
              startedAt: existing?.startedAt,
              realUsage: existing?.realUsage,
              machineName: payload['machine_name'] == null
                  ? existing?.machineName
                  : '${payload['machine_name']}',
              cwd: existing?.cwd ?? '',
              lastAssistantMessage: existing?.lastAssistantMessage ?? '',
              parentSessionId: parentFromPayload.isNotEmpty
                  ? parentFromPayload
                  : (existing?.parentSessionId ?? ''),
              source: existing?.source ?? '',
            ),
          );
        } else {
          state = state.copyWith(connected: true);
        }
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
    displayName: 'auth-service',
    state: SessionState.confirm,
    message: '优化登录逻辑，修复偶现问题',
    machineName: 'ThinkPad-X1',
    cwd: '/home/demo/projects/auth-service',
    lastAssistantMessage:
        '登录态偶现丢失的原因在刷新 token 竞态：并发请求同时发现过期后各自刷新，后写入覆盖了先写入的值。\n\n建议在刷新路径加单飞锁，并在 401 重试队列里复用同一次 refresh 结果。需要我直接改 `AuthInterceptor` 吗？',
    source: 'claude-hook',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    startedAt: DateTime.now().subtract(const Duration(minutes: 23)),
    realUsage: 86000,
  ),
  Session(
    machineId: 'm-macbook',
    agent: 'codex',
    sessionId: 's2',
    displayName: 'file-center',
    state: SessionState.working,
    message: '实现文件上传接口',
    machineName: 'MacBook-Pro',
    cwd: '/Users/demo/projects/file-center',
    lastAssistantMessage:
        '已按原型重新设计上传接口：\n\n- 支持分片与秒传\n- 校验 MIME 与大小上限\n- 补了集成测试\n\n接下来可以接前端进度条。',
    source: 'codex-file',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    startedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 12)),
    realUsage: 1200000,
  ),
  Session(
    machineId: 'm-macbook',
    agent: 'codex',
    sessionId: 's2-child-a',
    displayName: 'Maxwell',
    state: SessionState.working,
    message: '补充分片测试',
    machineName: 'MacBook-Pro',
    cwd: '/Users/demo/projects/file-center',
    lastAssistantMessage: '正在写 multipart 用例。',
    parentSessionId: 's2',
    source: 'codex-file',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 3)),
    startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
    realUsage: 12000,
  ),
  Session(
    machineId: 'm-macmini',
    agent: 'claude',
    sessionId: 's3',
    displayName: 'guide',
    state: SessionState.done,
    message: '更新文档说明',
    machineName: 'Mac mini',
    cwd: '/Users/demo/docs/guide',
    lastAssistantMessage: '文档已更新到 v3，并修正了安装步骤里的两处路径错误。',
    source: 'claude-hook',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 8)),
    startedAt: DateTime.now().subtract(const Duration(minutes: 45)),
    realUsage: 42000,
  ),
  Session(
    machineId: 'm-ubuntu',
    agent: 'codex',
    sessionId: 's4',
    displayName: 'analytics',
    state: SessionState.working,
    message: '重构数据统计模块',
    machineName: 'Ubuntu-Server',
    cwd: '/opt/apps/analytics',
    lastAssistantMessage: '正在把聚合查询拆成按日物化视图，下一步会补回填脚本。',
    source: 'codex-file',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 12)),
    startedAt: DateTime.now().subtract(const Duration(hours: 2)),
    realUsage: 256000,
  ),
  Session(
    machineId: 'm-thinkbook',
    agent: 'claude',
    sessionId: 's5',
    displayName: 'api',
    state: SessionState.idle,
    message: '整理接口文档',
    machineName: 'ThinkPad-X1',
    cwd: '/home/demo/docs/api',
    lastAssistantMessage: '',
    source: 'claude-hook',
    updatedAt: DateTime.now().subtract(const Duration(minutes: 30)),
    startedAt: DateTime.now().subtract(const Duration(hours: 3)),
    realUsage: 0,
  ),
  Session(
    machineId: 'm-macbook',
    agent: 'opencode',
    sessionId: 's6',
    displayName: 'dashboard',
    state: SessionState.idle,
    message: '修复样式兼容问题',
    machineName: 'MacBook-Pro',
    cwd: '/Users/demo/web/dashboard',
    lastAssistantMessage: 'Safari 下 flex gap 已改为 margin 方案，视觉对齐了。',
    source: 'codex-file',
    updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
    startedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 20)),
    realUsage: 3500,
  ),
  Session(
    machineId: 'm-macmini',
    agent: 'codex',
    sessionId: 's7',
    displayName: 'core',
    state: SessionState.idle,
    message: '更新依赖包版本',
    machineName: 'Mac mini',
    cwd: '/Users/demo/project/core',
    lastAssistantMessage: '依赖已升到兼容版本，CI 全绿。',
    source: 'codex-file',
    updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
    startedAt: DateTime.now().subtract(const Duration(hours: 4)),
    realUsage: 18000,
  ),
];
