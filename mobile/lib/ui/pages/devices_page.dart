import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';
import '../widgets/empty_state.dart';
import '../widgets/prototype_widgets.dart';
import '../widgets/status_dot.dart';
import '../widgets/task_card.dart';

class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(statusRepositoryProvider);
    final machines = snapshot.machines;

    return Scaffold(
      backgroundColor: context.qingya.scaffold,
      body: SafeArea(
        bottom: false,
        child: Column(
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
                    onTap: () =>
                        ref.read(statusRepositoryProvider.notifier).refresh(),
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
                      onRefresh: () =>
                          ref.read(statusRepositoryProvider.notifier).refresh(),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: machines.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final machine = machines[index];
                          final sessions =
                              snapshot.sessionsFor(machine.machineId);
                          final activeCount =
                              sessions.where((s) => s.state.isActive).length;
                          return _DeviceTile(
                            machine: machine,
                            activeCount: activeCount,
                            index: index,
                            onTap: () =>
                                context.push('/devices/${machine.machineId}'),
                            onRename: () => showRenameMachineDialog(
                              context,
                              ref,
                              machine,
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
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
  });

  final Machine machine;
  final int activeCount;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRename;

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
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        onLongPress: onRename,
        child: Container(
          height: 94,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: _backgroundOf(c),
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: c.border.withValues(alpha: 0.85)),
            boxShadow: [
              BoxShadow(
                  color: c.shadow,
                  blurRadius: 14,
                  offset: Offset(0, 5)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.card.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset(_deviceAsset, fit: BoxFit.contain),
              ),
              const SizedBox(width: 13),
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
                width: 62,
                height: 70,
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
  const DeviceDetailPage({super.key, required this.machineId});

  final String machineId;

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
                    onRename: machine == null
                        ? null
                        : () => showRenameMachineDialog(
                              context,
                              ref,
                              machine!,
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
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final session = active[index];
                  return TaskCard(
                    session: session,
                    onTap: () => context.push(
                      '/sessions/${session.machineId}/${session.agent}/${Uri.encodeComponent(session.sessionId)}',
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
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                  final session = idle[index];
                  return TaskCard(
                    session: session,
                    onTap: () => context.push(
                      '/sessions/${session.machineId}/${session.agent}/${Uri.encodeComponent(session.sessionId)}',
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
  });

  final Machine? machine;
  final String fallbackId;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final title = machine?.machineName ?? fallbackId;
    return SizedBox(
      height: 150,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 2,
            child: IconButton(
              onPressed: () => context.pop(),
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: context.qingya.textPrimary,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 54,
            right: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: context.qingya.textPrimary,
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
                          color: context.qingya.textSecondary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    OnlineDot(online: machine?.online == true, size: 8),
                    const SizedBox(width: 6),
                    Text(
                      machine?.online == true ? '在线' : '离线',
                      style: TextStyle(
                        color: machine?.online == true
                            ? context.qingya.online
                            : context.qingya.offline,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      ' · ',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.qingya.textSecondary,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        [
                          platformLabel(machine?.platform),
                          if ((machine?.version ?? '').isNotEmpty)
                            machine!.version,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.qingya.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                if ((machine?.version ?? '').isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    '监测端 ${machine!.version}',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.qingya.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  machine?.online == true
                      ? '最后心跳：1 分钟前'
                      : _lastSeen(machine?.lastSeenAt),
                  style: TextStyle(
                      fontSize: 11, color: context.qingya.textSecondary),
                ),
              ],
            ),
          ),
          Positioned(
            right: 4,
            bottom: 0,
            child: Image.asset(
              QingyaAssets.catDetailPeekV3,
              width: 128,
              height: 128,
              fit: BoxFit.contain,
            ),
          ),
        ],
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

