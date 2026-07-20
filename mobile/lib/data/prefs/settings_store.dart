import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models.dart';
import '../monitor/monitor_bridge.dart';

class SettingsStore extends StateNotifier<AppSettings> {
  SettingsStore(this._prefs) : super(const AppSettings()) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _kUrl = 'base_url';
  static const _kKey = 'api_key';
  static const _kConfirm = 'notify_confirm';
  static const _kWorking = 'notify_working';
  static const _kDone = 'notify_done';
  static const _kDemo = 'demo_mode';
  static const _kThemeMode = 'theme_mode';

  void _load() {
    state = AppSettings(
      baseUrl: _prefs.getString(_kUrl) ?? '',
      apiKey: _prefs.getString(_kKey) ?? '',
      notifyConfirm: _prefs.getBool(_kConfirm) ?? true,
      notifyWorking: _prefs.getBool(_kWorking) ?? true,
      notifyDone: _prefs.getBool(_kDone) ?? true,
      demoMode: _prefs.getBool(_kDemo) ?? false,
      themeMode: AppThemeMode.fromStorage(_prefs.getString(_kThemeMode)),
    );
    unawaited(MonitorBridge.apply(state));
  }

  Future<void> save(AppSettings next) async {
    await _prefs.setString(_kUrl, next.baseUrl.trim());
    await _prefs.setString(_kKey, next.apiKey.trim());
    await _prefs.setBool(_kConfirm, next.notifyConfirm);
    await _prefs.setBool(_kWorking, next.notifyWorking);
    await _prefs.setBool(_kDone, next.notifyDone);
    await _prefs.setBool(_kDemo, next.demoMode);
    await _prefs.setString(_kThemeMode, next.themeMode.storageValue);
    state = next.copyWith(
      baseUrl: next.baseUrl.trim(),
      apiKey: next.apiKey.trim(),
    );
    await MonitorBridge.apply(state);
  }

  Future<void> enableDemo() async {
    await save(state.copyWith(demoMode: true));
  }

  Future<void> updateFlags({
    bool? notifyConfirm,
    bool? notifyWorking,
    bool? notifyDone,
  }) async {
    await save(state.copyWith(
      notifyConfirm: notifyConfirm,
      notifyWorking: notifyWorking,
      notifyDone: notifyDone,
    ));
  }
}

final sharedPrefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('override in main');
});

final settingsProvider =
    StateNotifierProvider<SettingsStore, AppSettings>((ref) {
  return SettingsStore(ref.watch(sharedPrefsProvider));
});
