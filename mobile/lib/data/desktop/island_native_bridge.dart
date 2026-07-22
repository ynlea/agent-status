import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_platform.dart';
import 'island_models.dart';

/// 主引擎 ↔ 原生岛窗 桥接。
class IslandNativeBridge {
  IslandNativeBridge._();
  static final IslandNativeBridge instance = IslandNativeBridge._();

  static const _host = MethodChannel('qingya/island_host');

  final _openSessionCtrl = StreamController<Map<String, String>>.broadcast();
  final _showMainCtrl = StreamController<void>.broadcast();
  final _announcementDoneCtrl = StreamController<void>.broadcast();

  Stream<Map<String, String>> get openSession$ => _openSessionCtrl.stream;
  Stream<void> get showMain$ => _showMainCtrl.stream;
  Stream<void> get announcementDone$ => _announcementDoneCtrl.stream;

  bool _bound = false;

  Future<void> bind() async {
    if (!isQingyaDesktop || _bound) return;
    _bound = true;
    _host.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'open_session':
          final raw = call.arguments;
          if (raw is String) {
            final map = jsonDecode(raw) as Map<String, dynamic>;
            _openSessionCtrl.add({
              'machineId': '${map['machineId'] ?? ''}',
              'agent': '${map['agent'] ?? ''}',
              'sessionId': '${map['sessionId'] ?? ''}',
            });
          }
          return null;
        case 'show_main':
          _showMainCtrl.add(null);
          return null;
        case 'announcement_done':
          _announcementDoneCtrl.add(null);
          return null;
        default:
          return null;
      }
    });
  }

  Future<bool> ensure() async {
    if (!isQingyaDesktop) return false;
    try {
      final ok = await _host.invokeMethod<bool>('ensure');
      return ok == true;
    } catch (e) {
      debugPrint('[IslandNative] ensure: $e');
      return false;
    }
  }

  Future<void> show() async {
    if (!isQingyaDesktop) return;
    try {
      await _host.invokeMethod('show');
    } catch (e) {
      debugPrint('[IslandNative] show: $e');
    }
  }

  Future<void> hide() async {
    if (!isQingyaDesktop) return;
    try {
      await _host.invokeMethod('hide');
    } catch (e) {
      debugPrint('[IslandNative] hide: $e');
    }
  }

  Future<void> sync(IslandViewModel vm) async {
    if (!isQingyaDesktop) return;
    try {
      if (!vm.enabled || !vm.isVisible) {
        await hide();
        // 仍同步一次，便于子窗清空
        await _host.invokeMethod('sync', jsonEncode(vm.toJson()));
        return;
      }
      await ensure();
      await _host.invokeMethod('sync', jsonEncode(vm.toJson()));
      await show();
    } catch (e) {
      debugPrint('[IslandNative] sync: $e');
    }
  }
}
