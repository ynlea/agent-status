import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../desktop/desktop_pane.dart';
import '../widgets/assets.dart';
import '../widgets/empty_state.dart';
import '../widgets/prototype_widgets.dart';
import '../widgets/status_dot.dart';
import '../widgets/session_card.dart';

class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  String? _selectedMachineId;

  bool _useMasterDetail(BuildContext context) {
    if (!isQingyaDesktop) return false;
    return MediaQuery.sizeOf(context).width >= kDesktopMasterDetailBreakpoint;
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(statusRepositoryProvider);
    final machines = snapshot.machines;
    final masterDetail = _useMasterDetail(context);

    if (masterDetail &&
        _selectedMachineId != null &&
        machines.every((m) => m.machineId != _selectedMachineId)) {
      // 设备列表变更后清理失效选中
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMachineId = null);
      });
    }

    final listPane = _DevicesListPane(
      snapshot: snapshot,
      machines: machines,
      selectedMachineId: masterDetail ? _selectedMachineId : null,
      onSelect: (machine) {
        if (masterDetail) {
          setState(() => _selectedMachineId = machine.machineId);
        } else {
          context.push('/devices/${machine.machineId}');
        }
      },
      onRename: (machine) => showRenameMachineDialog(context, ref, machine),
      onRefresh: () => ref.read(statusRepositoryProvider.notifier).refresh(),
    );

    if (!masterDetail) {
      return Scaffold(
        backgroundColor: context.qingya.scaffold,
        body: SafeArea(bottom: false, child: listPane),
      );
    }

    final c = context.qingya;
    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 12),
          child: Row(
            children: [
              SizedBox(
                width: 360,
                child: DesktopPane(child: listPane),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DesktopPane(
                  child: _selectedMachineId == null
                      ? const DesktopPickHint(
                          asset: QingyaAssets.catEmptyDevices,
                          title: '选择一台设备',
                          subtitle: '右侧会显示会话与状态详情',
                        )
                      : DeviceDetailPage(
                          key: ValueKey(_selectedMachineId),
                          machineId: _selectedMachineId!,
                          embedded: true,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DevicesListPane extends StatelessWidget {
  const _DevicesListPane({
    required this.snapshot,
    required this.machines,
    required this.selectedMachineId,
    required this.onSelect,
    required this.onRename,
    required this.onRefresh,
  });

  final StatusSnapshot snapshot;
  final List<Machine> machines;
  final String? selectedMachineId;
  final ValueChanged<Machine> onSelect;
  final ValueChanged<Machine> onRename;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: QingyaBrandHeader(
            trailing: ConnectionPill(connected: snapshot.connected),
          ),
        ),
        const SizedBox(height: 26),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                '我的设备（${machines.length}）',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.qingya.textPrimary,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => onRefresh(),
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: QingyaTintIcon(QingyaAssets.refreshV2, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: machines.isEmpty
              ? const EmptyState(
                  asset: QingyaAssets.catDetailPeekV3,
                  title: '还没有设备',
                  subtitle: '等待监控端上报，或检查服务连接',
                )
              : RefreshIndicator(
                  color: context.qingya.device,
                  onRefresh: onRefresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: machines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final machine = machines[index];
                      final sessions =
                          snapshot.sessionsFor(machine.machineId);
                      final activeCount =
                          sessions.where((s) => s.state.isActive).length;
                      final selected = selectedMachineId == machine.machineId;
                      return _DeviceTile(
                        machine: machine,
                        activeCount: activeCount,
                        index: index,
                        selected: selected,
                        onTap: () => onSelect(machine),
                        onRename: () => onRename(machine),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.machine,
    required this.activeCount,
    required this.index,
    required this.onTap,
    required this.onRename,
    this.selected = false,
  });

  final Machine machine;
  final int activeCount;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final bool selected;

  String get _deviceAsset {
    final value = '${machine.platform} ${machine.machineName}'.toLowerCase();
    if (value.contains('thinkpad') || value.contains('thinkbook')) {
      return QingyaAssets.deviceThinkpadV2;
    }
    if (value.contains('macbook')) return QingyaAssets.deviceMacbookV2;
    if (value.contains('mac mini')) return QingyaAssets.deviceMacminiV2;
    if (value.contains('ubuntu')) return QingyaAssets.deviceUbuntuServerV2;
    if (value.contains('windows') || value.contains('desktop')) {
      return QingyaAssets.deviceWindowsPcV2;
    }
    if (value.contains('server')) return QingyaAssets.deviceServerV2;
    if (value.trim().isEmpty) return QingyaAssets.deviceUnknownV2;
    return QingyaAssets.deviceLaptopV2;
  }

  String get _catAsset => QingyaAssets.catForSeed(machine.machineId);

  Color _backgroundOf(QingyaPalette c) => [
        c.primarySoft,
        c.deviceSoft,
        c.doneSoft,
        c.workingSoft,
      ][index % 4];

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        onLongPress: onRename,
        child: Container(
          height: 86,
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: _backgroundOf(c),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? c.device.withValues(alpha: 0.9)
                  : c.border.withValues(alpha: 0.85),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                  color: c.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.card.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Image.asset(_deviceAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            machine.machineName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: context.qingya.textPrimary,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: onRename,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 15,
                              color: context.qingya.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        OnlineDot(online: machine.online, size: 7),
                        const SizedBox(width: 5),
                        Text(
                          machine.online ? '在线' : '离线',
                          style: TextStyle(
                            fontSize: 11,
                            color: machine.online
                                ? context.qingya.online
                                : context.qingya.offline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.qingya.textSecondary,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            [
                              platformLabel(machine.platform),
                              if (machine.version.isNotEmpty) machine.version,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: context.qingya.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      machine.online
                          ? '有 $activeCount 个活跃会话'
                          : _lastSeen(machine.lastSeenAt),
                      style: TextStyle(
                          fontSize: 11, color: context.qingya.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 52,
                height: 58,
                child: Image.asset(_catAsset, fit: BoxFit.contain),
              ),
              QingyaTintIcon(QingyaAssets.chevron, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}


String platformLabel(String? platform) {
  switch ((platform ?? '').trim().toLowerCase()) {
    case 'linux':
      return 'Linux';
    case 'windows':
    case 'win32':
    case 'win':
      return 'Windows';
    case 'darwin':
    case 'macos':
    case 'mac':
      return 'macOS';
    case 'android':
      return 'Android';
    case 'ios':
      return 'iOS';
    case '':
      return '未知系统';
    default:
      final raw = platform!.trim();
      if (raw.isEmpty) return '未知系统';
      return raw[0].toUpperCase() + raw.substring(1);
  }
}

String _lastSeen(DateTime? time) {
  if (time == null) return '最近未连接';
  final hours = DateTime.now().difference(time).inHours;
  if (hours < 1) return '最后在线：刚刚';
  if (hours < 24) return '最后在线：$hours 小时前';
  return '最后在线：${hours ~/ 24} 天前';
}

class DeviceDetailPage extends ConsumerStatefulWidget {
  const DeviceDetailPage({
    super.key,
    required this.machineId,
    this.embedded = false,
  });

  final String machineId;

  /// 桌面主从分栏右侧嵌入时为 true：隐藏返回按钮。
  final bool embedded;

  @override
  ConsumerState<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends ConsumerState<DeviceDetailPage> {
  bool _showIdle = true;

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(statusRepositoryProvider);
    Machine? machine;
    for (final item in snapshot.machines) {
      if (item.machineId == widget.machineId) {
        machine = item;
        break;
      }
    }
    final all = snapshot.sessionsFor(widget.machineId);
    final active = all.where((session) => session.state.isActive).toList();
    final idle = all.where((session) => !session.state.isActive).toList();

    return Scaffold(
      backgroundColor: context.qingya.scaffold,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  _DetailHeader(
                    machine: machine,
                    fallbackId: widget.machineId,
                    showBack: !widget.embedded,
                    onRename: machine == null
                        ? null
                        : () => showRenameMachineDialog(
                              context,
                              ref,
                              machine!,
                            ),
                  ),
                  const SizedBox(height: 12),
                  _ProvidersEntryCard(
                    onTap: () => context.push(
                      '/devices/${widget.machineId}/providers',
                    ),
                  ),
                  const SizedBox(height: 14),
                  _SessionSectionHeader(label: '活跃会话', count: active.length),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '当前没有活跃会话',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: context.qingya.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: active.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final session = active[index];
                  return SessionCard(
                    session: session,
                    onTap: () => context.push(
                      '/devices/${session.machineId}/sessions/${session.agent}/${Uri.encodeComponent(session.sessionId)}',
                    ),
                  );
                },
              ),
            ),
            if (idle.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                sliver: SliverList.list(
                  children: [
                    _SessionSectionHeader(
                      label: '空闲会话',
                      count: idle.length,
                      expanded: _showIdle,
                      onTap: () => setState(() => _showIdle = !_showIdle),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            if (_showIdle)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                sliver: SliverList.separated(
                  itemCount: idle.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                  final session = idle[index];
                  return SessionCard(
                    session: session,
                    onTap: () => context.push(
                      '/devices/${session.machineId}/sessions/${session.agent}/${Uri.encodeComponent(session.sessionId)}',
                    ),
                  );
                },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.machine,
    required this.fallbackId,
    this.onRename,
    this.showBack = true,
  });

  final Machine? machine;
  final String fallbackId;
  final VoidCallback? onRename;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final title = machine?.machineName ?? fallbackId;
    final version = (machine?.version ?? '').trim();
    final heartbeat = machine?.online == true
        ? '最后心跳：1 分钟前'
        : _lastSeen(machine?.lastSeenAt);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 112, bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showBack) ...[
                IconButton(
                  onPressed: () => context.pop(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  icon: Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 20,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
              ] else
                const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                        height: 1.2,
                      ),
                    ),
                  ),
                  if (onRename != null)
                    IconButton(
                      onPressed: onRename,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OnlineDot(online: machine?.online == true, size: 8),
                  const SizedBox(width: 6),
                  Text(
                    machine?.online == true ? '在线' : '离线',
                    style: TextStyle(
                      color: machine?.online == true ? c.online : c.offline,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    ' · ',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                  Flexible(
                    child: Text(
                      platformLabel(machine?.platform),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: c.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              if (version.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '监测端 $version',
                  style: TextStyle(
                    fontSize: 12,
                    color: c.textSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                heartbeat,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textSecondary,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Image.asset(
            QingyaAssets.catDetailPeekV3,
            width: 118,
            height: 118,
            fit: BoxFit.contain,
          ),
        ),
      ],
    );
  }
}

class _ProvidersEntryCard extends StatelessWidget {
  const _ProvidersEntryCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Material(
      color: c.card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: c.deviceSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(Icons.swap_horiz_rounded, size: 18, color: c.device),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '供应商 / cc-switch',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '查看、切换与编辑 Codex / Claude 供应商',
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              QingyaTintIcon(QingyaAssets.chevron, size: 14),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSectionHeader extends StatelessWidget {
  const _SessionSectionHeader({
    required this.label,
    required this.count,
    this.expanded,
    this.onTap,
  });

  final String label;
  final int count;
  final bool? expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(
              '$label（$count）',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.qingya.textPrimary,
              ),
            ),
            const Spacer(),
            if (expanded != null)
              QingyaTintIcon(
                expanded! ? QingyaAssets.collapse : QingyaAssets.expand,
                size: 17,
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> showRenameMachineDialog(
  BuildContext context,
  WidgetRef ref,
  Machine machine,
) async {
  final controller = TextEditingController(text: machine.machineName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) {
      final colors = ctx.qingya;
      return AlertDialog(
        title: const Text('给设备起个名字'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          style: TextStyle(fontSize: 14, color: colors.textPrimary),
          cursorColor: colors.device,
          decoration: InputDecoration(
            hintText: '例如：书房电脑 / 公司 Mac',
            counterText: '',
            filled: true,
            fillColor: colors.scaffold,
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (name == null || name.isEmpty || name == machine.machineName) return;
  try {
    await ref
        .read(statusRepositoryProvider.notifier)
        .renameMachine(machine.machineId, name);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已改名为「$name」')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      final c = context.qingya;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('改名失败：$e', style: TextStyle(color: c.confirm)),
        ),
      );
    }
  }
}

