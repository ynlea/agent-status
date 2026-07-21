import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../../theme/qingya_theme.dart';
import 'assets.dart';

/// 会话卡：状态 + Agent + 标题/路径 + 设备·时长·用量·更新时间。
class SessionCard extends StatelessWidget {
  const SessionCard({
    super.key,
    required this.session,
    this.onTap,
  });

  final Session session;
  final VoidCallback? onTap;

  String get _stateIcon => switch (session.state) {
        SessionState.confirm => QingyaAssets.notifyConfirm,
        SessionState.working => QingyaAssets.notifyWorking,
        SessionState.done => QingyaAssets.notifyDone,
        SessionState.idle => QingyaAssets.collapse,
      };

  String get _displayPath {
    final value = session.displayName.trim();
    if (value.isEmpty) return session.sessionId;
    return value.startsWith('/') ? value : '/$value';
  }

  _AgentStyle _agentOf(QingyaPalette c) {
    switch (session.agent.toLowerCase()) {
      case 'claude':
        return _AgentStyle(
          label: 'Claude',
          color: c.agentClaude,
          soft: c.agentClaudeSoft,
        );
      case 'codex':
        return _AgentStyle(
          label: 'Codex',
          color: c.agentCodex,
          soft: c.agentCodexSoft,
        );
      case 'opencode':
        return _AgentStyle(
          label: 'OpenCode',
          color: c.agentOpencode,
          soft: c.agentOpencodeSoft,
        );
      default:
        return _AgentStyle(
          label: session.agent.isEmpty ? 'Agent' : session.agent,
          color: c.textSecondary,
          soft: c.idleSoft,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final agent = _agentOf(c);
    final stateColor = switch (session.state) {
      SessionState.confirm => c.confirm,
      SessionState.working => c.working,
      SessionState.done => c.done,
      SessionState.idle => c.idle,
    };
    final stateSoft = switch (session.state) {
      SessionState.confirm => c.confirmSoft,
      SessionState.working => c.workingSoft,
      SessionState.done => c.doneSoft,
      SessionState.idle => c.idleSoft,
    };

    final metaParts = <String>[
      session.machineName ?? session.machineId,
      formatSessionDuration(session.startedAt),
      formatSessionTokens(session.realUsage),
      _relativeTime(session.updatedAt),
    ].where((e) => e.trim().isNotEmpty).toList();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 92),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: stateColor.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: c.shadow,
                blurRadius: 8,
                offset: const Offset(0, 3),
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
                      runSpacing: 4,
                      children: [
                        _Chip(
                          icon: _stateIcon,
                          label: session.state.labelZh,
                          color: stateColor,
                          soft: stateSoft,
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
                    const SizedBox(height: 6),
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      metaParts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: c.textSecondary,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClipOval(
                child: Image.asset(
                  QingyaAssets.agent(session.agent),
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 2),
                QingyaTintIcon(QingyaAssets.chevron, size: 14),
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
    final child = Image.asset(image, width: 12, height: 12);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(9),
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
          const SizedBox(width: 3),
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

/// 持续时长：`<1m` / `Nm` / `Nh Nm` / `Nd`；无开始时间返回 `—`。
String formatSessionDuration(DateTime? startedAt, {DateTime? now}) {
  if (startedAt == null) return '—';
  final base = now ?? DateTime.now();
  var minutes = base.difference(startedAt).inMinutes;
  if (minutes < 0) minutes = 0;
  if (minutes < 1) return '<1m';
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (hours < 24) {
    if (rem == 0) return '${hours}h';
    return '${hours}h ${rem}m';
  }
  final days = hours ~/ 24;
  return '${days}d';
}

/// Token 用量：原样 / `x.xk` / `x.xM`；无数据为 `—`。
String formatSessionTokens(int? realUsage) {
  if (realUsage == null || realUsage <= 0) return '—';
  if (realUsage < 1000) return '$realUsage';
  if (realUsage < 1000000) {
    final v = realUsage / 1000.0;
    final s = v >= 100 ? v.toStringAsFixed(0) : _trimOneDecimal(v);
    return '${s}k';
  }
  final v = realUsage / 1000000.0;
  final s = v >= 100 ? v.toStringAsFixed(0) : _trimOneDecimal(v);
  return '${s}M';
}

String _trimOneDecimal(double v) {
  final fixed = v.toStringAsFixed(1);
  if (fixed.endsWith('.0')) {
    return fixed.substring(0, fixed.length - 2);
  }
  return fixed;
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
