import 'package:flutter/material.dart';

import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';
// QingyaTintIcon lives in qingya_theme.dart

/// 桌面端显式刷新按钮（替代下拉刷新）。
class DesktopRefreshButton extends StatefulWidget {
  const DesktopRefreshButton({
    super.key,
    required this.onRefresh,
    this.tooltip = '刷新',
    this.size = 20,
  });

  final Future<void> Function() onRefresh;
  final String tooltip;
  final double size;

  @override
  State<DesktopRefreshButton> createState() => _DesktopRefreshButtonState();
}

class _DesktopRefreshButtonState extends State<DesktopRefreshButton> {
  bool _loading = false;

  Future<void> _run() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Tooltip(
      message: widget.tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _loading ? null : _run,
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: _loading
              ? SizedBox(
                  width: widget.size,
                  height: widget.size,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.primary,
                  ),
                )
              : QingyaTintIcon(
                  QingyaAssets.refreshV2,
                  size: widget.size,
                  color: c.textSecondary,
                ),
        ),
      ),
    );
  }
}
