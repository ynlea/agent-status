import 'package:flutter/material.dart';

import '../../theme/qingya_theme.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.asset,
    required this.title,
    this.subtitle,
  });

  final String asset;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 190, height: 150, fit: BoxFit.contain),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: c.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
