import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsHandler = void Function(String type, Map<String, dynamic> payload);

class WsClient {
  WsClient({required this.baseUrl, required this.apiKey});

  final String baseUrl;
  final String apiKey;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  WsHandler? onEvent;
  bool _closed = false;

  void connect() {
    _closed = false;
    _open();
  }

  void _open() {
    _sub?.cancel();
    _channel?.sink.close();
    var root = baseUrl.trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    if (root.startsWith('https://')) {
      root = 'wss://${root.substring('https://'.length)}';
    } else if (root.startsWith('http://')) {
      root = 'ws://${root.substring('http://'.length)}';
    }
    final uri = Uri.parse(
      '$root/api/v1/ws?key=${Uri.encodeComponent(apiKey.trim())}',
    );
    try {
      _channel = WebSocketChannel.connect(uri);
      _sub = _channel!.stream.listen(
        (raw) {
          try {
            final map = jsonDecode('$raw') as Map<String, dynamic>;
            final type = '${map['type'] ?? ''}';
            final payload = (map['payload'] as Map?)?.cast<String, dynamic>() ??
                <String, dynamic>{};
            onEvent?.call(type, payload);
          } catch (_) {}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), _open);
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnect?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
  }
}
