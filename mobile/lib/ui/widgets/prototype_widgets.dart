import 'package:flutter/material.dart';

import '../../theme/qingya_theme.dart';
import 'assets.dart';

/// 原型中各主页面共用的品牌顶栏。
class QingyaBrandHeader extends StatelessWidget {
  const QingyaBrandHeader({
    super.key,
    this.trailing,
    this.compact = false,
  });

  final Widget? trailing;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final avatarSize = compact ? 38.0 : 44.0;
    return Row(
      children: [
        Image.asset(
          QingyaAssets.catBrandAvatarV3,
          width: avatarSize,
          height: avatarSize,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '轻芽',
              style: TextStyle(
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Q I N G Y A',
              style: TextStyle(
                fontSize: 7,
                height: 1,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? c.online : c.offline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? '已连接' : '未连接',
            style: TextStyle(
              fontSize: 12,
              color: c.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class QingyaGroupCard extends StatelessWidget {
  const QingyaGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class QingyaSectionCaption extends StatelessWidget {
  const QingyaSectionCaption(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: c.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
