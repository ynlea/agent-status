import 'package:flutter/material.dart';

import '../../theme/qingya_theme.dart';

/// 桌面主从分栏用的圆角内容板。
class DesktopPane extends StatelessWidget {
  const DesktopPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.border.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }
}

/// 主从分栏右侧未选中时的轻提示。
class DesktopPickHint extends StatelessWidget {
  const DesktopPickHint({
    super.key,
    required this.asset,
    required this.title,
    required this.subtitle,
  });

  final String asset;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 120, height: 120, fit: BoxFit.contain),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: c.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
