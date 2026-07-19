import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import 'assets.dart';

/// 会话卡：状态徽标 + **Agent 强识别** + 摘要；右侧用 Agent 圆标区分 Claude / Codex。
class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.session,
    this.onTap,
  });

  final Session session;
  final VoidCallback? onTap;

  Color get _stateColor => switch (session.state) {
        SessionState.confirm => QingyaColors.confirm,
        SessionState.working => QingyaColors.working,
        SessionState.done => QingyaColors.done,
        SessionState.idle => QingyaColors.idle,
      };

  Color get _stateSoft => switch (session.state) {
        SessionState.confirm => QingyaColors.confirmSoft,
        SessionState.working => QingyaColors.workingSoft,
        SessionState.done => QingyaColors.doneSoft,
        SessionState.idle => QingyaColors.idleSoft,
      };

  String get _stateIcon => switch (session.state) {
        SessionState.confirm => QingyaAssets.notifyConfirm,
        SessionState.working => QingyaAssets.notifyWorking,
        SessionState.done => QingyaAssets.notifyDone,
        SessionState.idle => QingyaAssets.collapse,
      };

  _AgentStyle get _agent {
    switch (session.agent.toLowerCase()) {
      case 'claude':
        return const _AgentStyle(
          label: 'Claude',
          color: Color(0xFFD97757),
          soft: Color(0xFFFFF1EB),
        );
      case 'codex':
        return const _AgentStyle(
          label: 'Codex',
          color: Color(0xFF10A37F),
          soft: Color(0xFFE6F7F2),
        );
      case 'opencode':
        return const _AgentStyle(
          label: 'OpenCode',
          color: Color(0xFF6078FF),
          soft: Color(0xFFEEF1FF),
        );
      default:
        return _AgentStyle(
          label: session.agent.isEmpty ? 'Agent' : session.agent,
          color: QingyaColors.textSecondary,
          soft: QingyaColors.idleSoft,
        );
    }
  }

  String get _displayPath {
    final value = session.displayName.trim();
    if (value.isEmpty) return session.sessionId;
    return value.startsWith('/') ? value : '/$value';
  }

  @override
  Widget build(BuildContext context) {
    final agent = _agent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 108),
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            color: QingyaColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _stateColor.withValues(alpha: 0.18)),
            boxShadow: const [
              BoxShadow(
                color: QingyaColors.shadow,
                blurRadius: 14,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Chip(
                          icon: _stateIcon,
                          label: session.state.labelZh,
                          color: _stateColor,
                          soft: _stateSoft,
                          tintIcon: true,
                        ),
                        _Chip(
                          asset: QingyaAssets.agentGlyph(session.agent),
                          label: agent.label,
                          color: agent.color,
                          soft: agent.soft,
                          tintIcon: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: QingyaColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: QingyaColors.textSecondary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${session.machineName ?? session.machineId} · ${_relativeTime(session.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: QingyaColors.textSecondary,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // 右侧官方 Agent 圆标（Claude 星芒 / OpenAI·Codex）
              ClipOval(
                child: Image.asset(
                  QingyaAssets.agent(session.agent),
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Image.asset(QingyaAssets.chevron, width: 14, height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentStyle {
  const _AgentStyle({
    required this.label,
    required this.color,
    required this.soft,
  });

  final String label;
  final Color color;
  final Color soft;
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.soft,
    required this.tintIcon,
    this.icon,
    this.asset,
  });

  final String label;
  final Color color;
  final Color soft;
  final bool tintIcon;
  final String? icon;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final image = asset ?? icon!;
    final child = Image.asset(image, width: 13, height: 13);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tintIcon)
            ColorFiltered(
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
              child: child,
            )
          else
            child,
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              height: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(DateTime? time) {
  if (time == null) return '刚刚';
  final minutes = DateTime.now().difference(time).inMinutes;
  if (minutes <= 0) return '刚刚';
  if (minutes < 60) return '$minutes 分钟前';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours 小时前';
  return '${hours ~/ 24} 天前';
}
