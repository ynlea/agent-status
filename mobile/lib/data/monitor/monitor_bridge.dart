import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../domain/models.dart';

/// Bridges Flutter settings to the Android `:monitor` foreground service.
class MonitorBridge {
  MonitorBridge._();

  static const _channel = MethodChannel('qingya/monitor');

  // Use dart:io Platform so widget tests on Linux/macOS skip the channel
  // (defaultTargetPlatform is often android in tests).
  static bool get _android => !kIsWeb && Platform.isAndroid;

  static String? lastError;
  static String lastStatus = '未同步';

  static Future<void> apply(AppSettings settings) async {
    if (!_android) {
      lastStatus = '非 Android';
      return;
    }
    try {
      // Demo: pause service but keep last real config for later restore / reboot.
      if (settings.demoMode) {
        await _channel.invokeMethod('stop');
        lastError = null;
        lastStatus = '演示模式（后台已暂停）';
        debugPrint('[MonitorBridge] stop for demo');
        return;
      }
      final url = settings.baseUrl.trim();
      final key = settings.apiKey.trim();
      final result = await _channel.invokeMethod<dynamic>(
        'syncAndStart',
        <String, dynamic>{
          'serverUrl': url,
          'apiKey': key,
          'notifyConfirm': settings.notifyConfirm,
          'notifyWorking': settings.notifyWorking,
          'notifyDone': settings.notifyDone,
        },
      );
      lastError = null;
      final map = result is Map ? result.cast<dynamic, dynamic>() : const {};
      final started = map['started'] == true;
      final perm = map['notificationPermission'];
      if (url.isEmpty || key.isEmpty) {
        lastStatus = '未配置服务';
      } else if (started) {
        lastStatus = perm == false ? '已启动（请允许通知权限）' : '后台监测已启动';
      } else {
        lastStatus = '未启动';
      }
      debugPrint('[MonitorBridge] apply => $lastStatus raw=$result');
    } catch (e, st) {
      lastError = '$e';
      lastStatus = '启动失败';
      debugPrint('[MonitorBridge] apply failed: $e\n$st');
    }
  }

  static Future<Map<String, dynamic>> status() async {
    if (!_android) return {'configured': false};
    try {
      final result = await _channel.invokeMethod<dynamic>('status');
      if (result is Map) {
        return result.map((k, v) => MapEntry('$k', v));
      }
    } catch (e) {
      lastError = '$e';
    }
    return {'configured': false, 'error': lastError};
  }

  static Future<void> stop() async {
    if (!_android) return;
    try {
      await _channel.invokeMethod<void>('stop');
      lastStatus = '已停止';
    } catch (e) {
      lastError = '$e';
      debugPrint('[MonitorBridge] stop failed: $e');
    }
  }
}
