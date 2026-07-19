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
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '轻芽',
              style: TextStyle(
                fontSize: 21,
                height: 1,
                fontWeight: FontWeight.w700,
                color: QingyaColors.textPrimary,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Q I N G Y A',
              style: TextStyle(
                fontSize: 7,
                height: 1,
                fontWeight: FontWeight.w600,
                color: QingyaColors.textSecondary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QingyaColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: connected ? QingyaColors.online : QingyaColors.offline,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? '已连接' : '未连接',
            style: const TextStyle(
              fontSize: 12,
              color: QingyaColors.textPrimary,
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
    return Container(
      decoration: BoxDecoration(
        color: QingyaColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QingyaColors.border.withValues(alpha: 0.75)),
        boxShadow: const [
          BoxShadow(
            color: QingyaColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 7),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 9),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          color: QingyaColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
