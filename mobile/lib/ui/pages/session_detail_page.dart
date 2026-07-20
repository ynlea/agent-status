import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repo/status_repository.dart';
import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/status_dot.dart';

/// 会话详情：展示用，无操作按钮。
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
    final machineLabel = (machine?.machineName.isNotEmpty == true)
        ? machine!.machineName
        : (session?.machineName?.isNotEmpty == true
            ? session!.machineName!
            : machineId);
    final online = machine?.online ?? false;
    final state = session?.state ?? SessionState.idle;
    final c = context.qingya;
    final agentLabel = _agentLabel(session?.agent ?? agent);
    final time = _relativeTime(session?.updatedAt);

    return Scaffold(
      backgroundColor: c.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // 顶栏
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                      color: c.textPrimary,
                    ),
                  ),
                  Text(
                    '会话',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  _SoftChip(
                    label: state.labelZh,
                    color: _stateColor(c, state),
                    soft: _stateSoft(c, state),
                  ),
                  const SizedBox(width: 6),
                  _SoftChip(
                    label: agentLabel,
                    color: _agentColor(c, agent),
                    soft: _agentSoft(c, agent),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // 标题卡
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _stateSoft(c, state),
                          context.qingya.card,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _stateColor(c, state).withValues(alpha: 0.18),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: context.qingya.shadow,
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.qingya.textPrimary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _MetaRow(
                          icon: Icons.computer_rounded,
                          child: Row(
                            children: [
                              OnlineDot(online: online, size: 7),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  [
                                    machineLabel,
                                    online ? '在线' : '离线',
                                    if (time.isNotEmpty) time,
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
                        ),
                        if (path.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _MetaRow(
                            icon: Icons.folder_open_rounded,
                            child: Text(
                              path,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: context.qingya.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Container(
                        width: 4,
                        height: 14,
                        decoration: BoxDecoration(
                          color: context.qingya.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Agent 最后消息',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: context.qingya.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 120),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                    decoration: BoxDecoration(
                      color: context.qingya.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: context.qingya.border),
                      boxShadow: [
                        BoxShadow(
                          color: context.qingya.shadow,
                          blurRadius: 14,
                          offset: Offset(0, 5),
                        ),
                      ],
                    ),
                    child: body.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 28),
                              child: Text(
                                '暂无 Agent 输出',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.qingya.textSecondary,
                                ),
                              ),
                            ),
                          )
                        : MarkdownBody(
                            data: body,
                            selectable: true,
                            softLineBreak: true,
                            styleSheet: MarkdownStyleSheet(
                              p: TextStyle(
                                fontSize: 14.5,
                                height: 1.55,
                                color: context.qingya.textPrimary,
                              ),
                              h1: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: context.qingya.textPrimary,
                                height: 1.35,
                              ),
                              h2: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: context.qingya.textPrimary,
                                height: 1.35,
                              ),
                              h3: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: context.qingya.textPrimary,
                                height: 1.35,
                              ),
                              strong: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.qingya.textPrimary,
                              ),
                              em: TextStyle(
                                fontStyle: FontStyle.italic,
                                color: context.qingya.textPrimary,
                              ),
                              code: TextStyle(
                                fontSize: 13,
                                fontFamily: 'monospace',
                                color: context.qingya.primaryDark,
                                backgroundColor: context.qingya.primarySoft,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: context.qingya.idleSoft,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.qingya.border),
                              ),
                              codeblockPadding: const EdgeInsets.all(12),
                              blockquote: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: context.qingya.textSecondary,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                border: Border(
                                  left: BorderSide(
                                    color: context.qingya.primary,
                                    width: 3,
                                  ),
                                ),
                              ),
                              blockquotePadding:
                                  const EdgeInsets.fromLTRB(12, 4, 0, 4),
                              listBullet: TextStyle(
                                fontSize: 14.5,
                                color: context.qingya.textPrimary,
                              ),
                              a: TextStyle(
                                color: context.qingya.device,
                                decoration: TextDecoration.underline,
                              ),
                              tableHead: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: context.qingya.textPrimary,
                              ),
                              tableBody: TextStyle(
                                color: context.qingya.textPrimary,
                              ),
                              horizontalRuleDecoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(
                                    color: context.qingya.divider,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: context.qingya.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: child),
      ],
    );
  }
}

class _SoftChip extends StatelessWidget {
  const _SoftChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

Color _stateColor(QingyaPalette c, SessionState s) => switch (s) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      SessionState.idle => c.idle,
    };

Color _stateSoft(QingyaPalette c, SessionState s) => switch (s) {
      SessionState.confirm => c.confirmSoft,
      SessionState.working => c.workingSoft,
      SessionState.done => c.doneSoft,
      SessionState.idle => c.idleSoft,
    };

String _agentLabel(String agent) => switch (agent.toLowerCase()) {
      'claude' => 'Claude',
      'codex' => 'Codex',
      'opencode' => 'OpenCode',
      _ => agent.isEmpty ? 'Agent' : agent,
    };

Color _agentColor(QingyaPalette c, String agent) => switch (agent.toLowerCase()) {
      'claude' => c.agentClaude,
      'codex' => c.agentCodex,
      'opencode' => c.agentOpencode,
      _ => c.device,
    };

Color _agentSoft(QingyaPalette c, String agent) => switch (agent.toLowerCase()) {
      'claude' => c.agentClaudeSoft,
      'codex' => c.agentCodexSoft,
      'opencode' => c.agentOpencodeSoft,
      _ => c.deviceSoft,
    };

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
