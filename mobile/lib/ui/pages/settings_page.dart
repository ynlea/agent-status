import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/monitor/monitor_bridge.dart';
import '../../data/prefs/package_info_provider.dart';
import '../../data/prefs/settings_store.dart';
import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';
import '../widgets/prototype_widgets.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  String _monitorStatus = MonitorBridge.lastStatus;

  Future<void> _refreshMonitorLabel() async {
    final s = ref.read(settingsProvider);
    await MonitorBridge.apply(s);
    if (!mounted) return;
    setState(() => _monitorStatus = MonitorBridge.lastStatus);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshMonitorLabel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final settings = ref.watch(settingsProvider);
    final snapshot = ref.watch(statusRepositoryProvider);
    final allNotifications =
        settings.notifyConfirm && settings.notifyWorking && settings.notifyDone;

    Future<void> save(AppSettings next) async {
      await ref.read(settingsProvider.notifier).save(next);
      await ref.read(statusRepositoryProvider.notifier).refresh();
      await _refreshMonitorLabel();
    }

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            QingyaBrandHeader(
              trailing: ConnectionPill(connected: snapshot.connected),
            ),
            const SizedBox(height: 26),
            const QingyaSectionCaption('连接设置'),
            QingyaGroupCard(
              children: [
                _SettingsValueRow(
                  label: '服务地址',
                  value: settings.baseUrl.isEmpty ? '未配置' : settings.baseUrl,
                  onTap: () => context.push('/setup'),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.divider),
                _SettingsValueRow(
                  label: '访问密钥',
                  value: settings.apiKey.isEmpty ? '未配置' : '••••••••••••',
                  onTap: () => context.push('/setup'),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.divider),
                _SettingsValueRow(
                  label: '后台监测',
                  value: _monitorStatus,
                  onTap: _refreshMonitorLabel,
                ),
              ],
            ),
            const SizedBox(height: 22),
            const QingyaSectionCaption('通知设置'),
            QingyaGroupCard(
              children: [
                _SettingsSwitchRow(
                  label: '接收通知（总开关）',
                  value: allNotifications,
                  onChanged: (value) => save(
                    settings.copyWith(
                      notifyConfirm: value,
                      notifyWorking: value,
                      notifyDone: value,
                    ),
                  ),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.divider),
                _SettingsSwitchRow(
                  label: '需确认（红色）',
                  dotColor: c.confirm,
                  value: settings.notifyConfirm,
                  onChanged: (value) =>
                      save(settings.copyWith(notifyConfirm: value)),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.divider),
                _SettingsSwitchRow(
                  label: '工作中（黄色）',
                  dotColor: c.working,
                  value: settings.notifyWorking,
                  onChanged: (value) =>
                      save(settings.copyWith(notifyWorking: value)),
                ),
                Divider(height: 1, indent: 12, endIndent: 12, color: c.divider),
                _SettingsSwitchRow(
                  label: '已完成（绿色）',
                  dotColor: c.done,
                  value: settings.notifyDone,
                  onChanged: (value) =>
                      save(settings.copyWith(notifyDone: value)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '成功时通知栏会出现「轻芽后台监听」。请允许通知权限；点「后台监测」可重新拉起。演示模式不会启真实后台。',
                style: TextStyle(
                  fontSize: 11,
                  color: c.textSecondary,
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(height: 22),
            const QingyaSectionCaption('外观设置'),
            QingyaGroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '主题模式',
                        style: TextStyle(
                          fontSize: 13,
                          color: c.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<AppThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: AppThemeMode.system,
                            label: Text('跟随系统'),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.light,
                            label: Text('浅色'),
                          ),
                          ButtonSegment(
                            value: AppThemeMode.dark,
                            label: Text('深色'),
                          ),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (next) {
                          if (next.isEmpty) return;
                          save(settings.copyWith(themeMode: next.first));
                        },
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const QingyaSectionCaption('关于'),
            QingyaGroupCard(
              children: [
                _SettingsValueRow(
                  label: '版本信息',
                  value: ref.watch(packageInfoProvider).when(
                        data: (info) => info.versionWithBuild,
                        loading: () => '…',
                        error: (_, __) => 'v0.1.6',
                      ),
                ),
                if (settings.demoMode) ...[
                  Divider(
                      height: 1, indent: 12, endIndent: 12, color: c.divider),
                  _SettingsValueRow(
                    label: '演示数据',
                    value: '退出演示',
                    onTap: () async {
                      await save(settings.copyWith(demoMode: false));
                      if (context.mounted) context.go('/welcome');
                    },
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsValueRow extends StatelessWidget {
  const _SettingsValueRow({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: c.textSecondary),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              QingyaTintIcon(QingyaAssets.chevron, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.dotColor,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 5, 8, 5),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: c.textPrimary),
            ),
          ),
          Transform.scale(
            scale: 0.85,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
