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
      backgroundColor: QingyaColors.scaffold,
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: QingyaColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () =>
                        ref.read(statusRepositoryProvider.notifier).refresh(),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Image.asset(QingyaAssets.refreshV2,
                          width: 20, height: 20),
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
                      color: QingyaColors.device,
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
  });

  final Machine machine;
  final int activeCount;
  final int index;
  final VoidCallback onTap;

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

  Color get _background => [
        const Color(0xFFFFF8F4),
        const Color(0xFFF6FAFF),
        const Color(0xFFF7FBF7),
        const Color(0xFFFFFAF2),
      ][index % 4];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 94,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: _background,
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: QingyaColors.border.withValues(alpha: 0.85)),
            boxShadow: const [
              BoxShadow(
                  color: QingyaColors.shadow,
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
                  color: Colors.white.withValues(alpha: 0.82),
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
                    Text(
                      machine.machineName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: QingyaColors.textPrimary,
                      ),
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
                                ? QingyaColors.online
                                : QingyaColors.offline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 11,
                            color: QingyaColors.textSecondary,
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
                            style: const TextStyle(
                              fontSize: 11,
                              color: QingyaColors.textSecondary,
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
                      style: const TextStyle(
                          fontSize: 11, color: QingyaColors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 62,
                height: 70,
                child: Image.asset(_catAsset, fit: BoxFit.contain),
              ),
              Image.asset(QingyaAssets.chevron, width: 14, height: 14),
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
      backgroundColor: QingyaColors.scaffold,
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.list(
                children: [
                  _DetailHeader(machine: machine, fallbackId: widget.machineId),
                  const SizedBox(height: 14),
                  _SessionSectionHeader(label: '活跃会话', count: active.length),
                  const SizedBox(height: 8),
                  if (active.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Text(
                        '当前没有活跃会话',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: QingyaColors.textSecondary),
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
  const _DetailHeader({required this.machine, required this.fallbackId});

  final Machine? machine;
  final String fallbackId;

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
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: QingyaColors.textPrimary,
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
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: QingyaColors.textPrimary,
                  ),
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
                            ? QingyaColors.online
                            : QingyaColors.offline,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Text(
                      ' · ',
                      style: TextStyle(
                        fontSize: 12,
                        color: QingyaColors.textSecondary,
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: QingyaColors.textSecondary,
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
                    style: const TextStyle(
                      fontSize: 11,
                      color: QingyaColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 7),
                Text(
                  machine?.online == true
                      ? '最后心跳：1 分钟前'
                      : _lastSeen(machine?.lastSeenAt),
                  style: const TextStyle(
                      fontSize: 11, color: QingyaColors.textSecondary),
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
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: QingyaColors.textPrimary,
              ),
            ),
            const Spacer(),
            if (expanded != null)
              Image.asset(
                expanded! ? QingyaAssets.collapse : QingyaAssets.expand,
                width: 17,
                height: 17,
              ),
          ],
        ),
      ),
    );
  }
}
