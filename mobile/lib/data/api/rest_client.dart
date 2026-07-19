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
