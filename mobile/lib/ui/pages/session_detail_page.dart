import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/status_dot.dart';

/// 会话详情：头部元信息 + 完整 Agent 最后消息。
class SessionDetailPage extends ConsumerWidget {
  const SessionDetailPage({
    super.key,
    required this.machineId,
    required this.agent,
    required this.sessionId,
  });

  final String machineId;
  final String agent;
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(statusRepositoryProvider);
    Session? session;
    for (final s in snapshot.sessions) {
      if (s.machineId == machineId &&
          s.agent == agent &&
          s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    // 兼容 demo / 列表短暂不同步
    session ??= snapshot.sessions.cast<Session?>().firstWhere(
          (s) =>
              s != null &&
              s.machineId == machineId &&
              s.sessionId == sessionId,
          orElse: () => null,
        );

    Machine? machine;
    for (final m in snapshot.machines) {
      if (m.machineId == machineId) {
        machine = m;
        break;
      }
    }

    final title = session?.title ?? sessionId;
    final path = session?.projectPath ?? '';
    final body = session?.lastAssistantMessage.trim() ?? '';
    final machineLabel =
        session?.machineName?.trim().isNotEmpty == true
            ? session!.machineName!
            : (machine?.machineName.isNotEmpty == true
                ? machine!.machineName
                : machineId);

    return Scaffold(
      backgroundColor: QingyaColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: QingyaColors.textPrimary,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      '会话详情',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: QingyaColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                children: [
                  _HeaderCard(
                    session: session,
                    title: title,
                    machineLabel: machineLabel,
                    path: path,
                    agent: agent,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Agent 最后消息',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: QingyaColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    decoration: BoxDecoration(
                      color: QingyaColors.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: QingyaColors.border),
                      boxShadow: const [
                        BoxShadow(
                          color: QingyaColors.shadow,
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: body.isEmpty
                        ? const Text(
                            '暂无 Agent 输出',
                            style: TextStyle(
                              fontSize: 13,
                              color: QingyaColors.textSecondary,
                            ),
                          )
                        : SelectableText(
                            body,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: QingyaColors.textPrimary,
                            ),
                          ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: body.isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: body));
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('已复制最后消息')),
                                    );
                                  }
                                },
                          child: const Text('复制最后消息'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () =>
                              context.push('/devices/$machineId'),
                          child: const Text('查看所属设备'),
                        ),
                      ),
                    ],
                  ),
                  if (session != null) ...[
                    const SizedBox(height: 18),
                    _MoreBlock(session: session!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.session,
    required this.title,
    required this.machineLabel,
    required this.path,
    required this.agent,
  });

  final Session? session;
  final String title;
  final String machineLabel;
  final String path;
  final String agent;

  Color get _stateColor {
    switch (session?.state) {
      case SessionState.confirm:
        return QingyaColors.confirm;
      case SessionState.working:
        return QingyaColors.working;
      case SessionState.done:
        return QingyaColors.done;
      default:
        return QingyaColors.idle;
    }
  }

  Color get _stateSoft {
    switch (session?.state) {
      case SessionState.confirm:
        return QingyaColors.confirmSoft;
      case SessionState.working:
        return QingyaColors.workingSoft;
      case SessionState.done:
        return QingyaColors.doneSoft;
      default:
        return QingyaColors.idleSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final stateLabel = session?.state.labelZh ?? '空闲';
    final agentLabel = switch (agent.toLowerCase()) {
      'claude' => 'Claude',
      'codex' => 'Codex',
      'opencode' => 'OpenCode',
      _ => agent.isEmpty ? 'Agent' : agent,
    };
    final time = _relativeTime(session?.updatedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QingyaColors.border),
        boxShadow: const [
          BoxShadow(
            color: QingyaColors.shadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _MiniChip(
                label: stateLabel,
                color: _stateColor,
                soft: _stateSoft,
              ),
              _MiniChip(
                label: agentLabel,
                color: QingyaColors.device,
                soft: QingyaColors.deviceSoft,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: QingyaColors.textPrimary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OnlineDot(online: true, size: 7),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    machineLabel,
                    if (time.isNotEmpty) time,
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
          const SizedBox(height: 12),
          const Text(
            '路径',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: QingyaColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: path.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: path));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制路径')),
                      );
                    }
                  },
            child: Text(
              path.isEmpty ? '—' : path,
              style: const TextStyle(
                fontSize: 12,
                height: 1.35,
                color: QingyaColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreBlock extends StatelessWidget {
  const _MoreBlock({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 4),
        title: const Text(
          '更多',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: QingyaColors.textSecondary,
          ),
        ),
        children: [
          _kv('session_id', session.sessionId),
          if (session.source.isNotEmpty) _kv('source', session.source),
          _kv('agent', session.agent),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              k,
              style: const TextStyle(
                fontSize: 11,
                color: QingyaColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              v,
              style: const TextStyle(
                fontSize: 11,
                color: QingyaColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({
    required this.label,
    required this.color,
    required this.soft,
  });

  final String label;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

String _relativeTime(DateTime? t) {
  if (t == null) return '';
  final sec = DateTime.now().difference(t.toLocal()).inSeconds;
  if (sec < 45) return '刚刚';
  if (sec < 90) return '1 分钟前';
  if (sec < 3600) return '${sec ~/ 60} 分钟前';
  if (sec < 90 * 60) return '1 小时前';
  if (sec < 24 * 3600) return '${sec ~/ 3600} 小时前';
  return '${sec ~/ (24 * 3600)} 天前';
}
