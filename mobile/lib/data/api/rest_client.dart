import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models.dart';

class RestClient {
  RestClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  /// 规范化用户输入：去空白、去尾 `/`、去掉误填的 `/api` 后缀。
  String get _root {
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    // 用户若填了 https://host/api 或 /api/v1，收到根域名
    if (root.endsWith('/api/v1')) {
      root = root.substring(0, root.length - '/api/v1'.length);
    } else if (root.endsWith('/api')) {
      root = root.substring(0, root.length - '/api'.length);
    }
    return root;
  }

  Uri _u(String path) => Uri.parse('$_root$path');

  Map<String, String> get _headers => {
        'Authorization': 'Bearer ${apiKey.trim()}',
        'X-Agent-Status-Key': apiKey.trim(),
        'Accept': 'application/json',
      };

  Future<List<Machine>> fetchMachines() async {
    final res = await http
        .get(_u('/api/v1/machines'), headers: _headers)
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list =
        (body['machines'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list.map(Machine.fromJson).toList();
  }

  Future<List<Session>> fetchSessions(String machineId) async {
    final res = await http
        .get(
          _u('/api/v1/machines/${Uri.encodeComponent(machineId)}/sessions'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list =
        (body['sessions'] as List? ?? const []).cast<Map<String, dynamic>>();
    return list
        .map((e) => Session.fromJson({...e, 'machine_id': machineId}))
        .toList();
  }

  /// 修改设备显示名（服务端锁定，监测端上报不再覆盖）。
  Future<Machine> renameMachine(String machineId, String name) async {
    final res = await http
        .patch(
          _u('/api/v1/machines/${Uri.encodeComponent(machineId)}'),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'machine_name': name}),
        )
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final m = body['machine'];
    if (m is Map<String, dynamic>) {
      return Machine.fromJson(m);
    }
    return Machine.fromJson({
      'machine_id': machineId,
      'machine_name': name,
    });
  }

  Future<UsageSummary> fetchUsageSummary({
    required DateTime from,
    required DateTime to,
    String? machineId,
    String? agent,
    String? model,
  }) async {
    final res = await http
        .get(
          _usageUri('/api/v1/usage/summary', from, to,
              machineId: machineId, agent: agent, model: model),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(res);
    return UsageSummary.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<UsageBreakdown> fetchUsageBreakdown({
    required DateTime from,
    required DateTime to,
    String groupBy = 'model',
    String? machineId,
    String? agent,
    String? model,
  }) async {
    final res = await http
        .get(
          _usageUri(
            '/api/v1/usage/breakdown',
            from,
            to,
            machineId: machineId,
            agent: agent,
            model: model,
            groupBy: groupBy,
          ),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 30));
    _ensureOk(res);
    return UsageBreakdown.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Uri _usageUri(
    String path,
    DateTime from,
    DateTime to, {
    String? machineId,
    String? agent,
    String? model,
    String? groupBy,
  }) {
    final q = <String, String>{
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
    };
    if (machineId != null && machineId.isNotEmpty) {
      q['machine_id'] = machineId;
    }
    if (agent != null && agent.isNotEmpty) {
      q['agent'] = agent;
    }
    if (model != null && model.isNotEmpty) {
      q['model'] = model;
    }
    if (groupBy != null && groupBy.isNotEmpty) {
      q['group_by'] = groupBy;
    }
    return _u(path).replace(queryParameters: q);
  }

  Future<ProvidersListResponse> fetchProviders(
    String machineId, {
    String app = 'all',
  }) async {
    final uri = _u(
      '/api/v1/machines/${Uri.encodeComponent(machineId)}/providers',
    ).replace(queryParameters: {'app': app});
    final res = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    return ProvidersListResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  Future<String> enqueueCommand({
    required String machineId,
    required String app,
    required String type,
    required Map<String, dynamic> payload,
  }) async {
    final res = await http
        .post(
          _u('/api/v1/machines/${Uri.encodeComponent(machineId)}/commands'),
          headers: {
            ..._headers,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'app': app,
            'type': type,
            'payload': payload,
          }),
        )
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return '${body['command_id'] ?? ''}';
  }

  Future<MachineCommand> fetchCommand(String commandId) async {
    final res = await http
        .get(
          _u('/api/v1/commands/${Uri.encodeComponent(commandId)}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 20));
    _ensureOk(res);
    return MachineCommand.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
  }

  /// Enqueue and poll until terminal status (or timeout).
  Future<MachineCommand> runCommandAndWait({
    required String machineId,
    required String app,
    required String type,
    required Map<String, dynamic> payload,
    Duration timeout = const Duration(seconds: 90),
    Duration interval = const Duration(seconds: 2),
  }) async {
    final id = await enqueueCommand(
      machineId: machineId,
      app: app,
      type: type,
      payload: payload,
    );
    if (id.isEmpty) {
      throw RestException(500, '服务端未返回 command_id');
    }
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final cmd = await fetchCommand(id);
      if (cmd.isTerminal) return cmd;
      await Future<void>.delayed(interval);
    }
    return MachineCommand(
      id: id,
      machineId: machineId,
      app: app,
      type: type,
      status: 'timed_out',
      errorMessage: '等待命令结果超时',
    );
  }

  void _ensureOk(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    if (res.statusCode == 401) {
      throw RestException(
        res.statusCode,
        '密钥无效或未填写（401）。请确认与服务端 AGENT_STATUS_KEY 一致',
      );
    }
    throw RestException(res.statusCode, res.body);
  }
}

class RestException implements Exception {
  RestException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => body.isNotEmpty ? body : 'HTTP $statusCode';
}
