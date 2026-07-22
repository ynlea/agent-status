import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

/// 自定义标题栏：拖拽、最小化、最大化、关闭（走 preventClose → 托盘）。
class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({super.key});

  static const double height = 40;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (isQingyaDesktop) {
      windowManager.addListener(this);
      unawaited(_syncMax());
    }
  }

  @override
  void dispose() {
    if (isQingyaDesktop) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncMax() async {
    final m = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = m);
  }

  @override
  void onWindowMaximize() => _syncMax();

  @override
  void onWindowUnmaximize() => _syncMax();

  @override
  void onWindowRestore() => _syncMax();

  @override
  Widget build(BuildContext context) {
    if (!isQingyaDesktop) return const SizedBox.shrink();
    final c = context.qingya;

    return Material(
      color: c.card,
      child: SizedBox(
        height: DesktopTitleBar.height,
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          QingyaAssets.catAppIcon,
                          width: 18,
                          height: 18,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Image.asset(
                            QingyaAssets.catBrandAvatarV3,
                            width: 18,
                            height: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '轻芽',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'QINGYA',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                          color: c.textSecondary,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _TitleBtn(
              icon: Icons.remove_rounded,
              tooltip: '最小化',
              onTap: () => windowManager.minimize(),
            ),
            _TitleBtn(
              icon: _maximized
                  ? Icons.filter_none_rounded
                  : Icons.crop_square_rounded,
              tooltip: _maximized ? '还原' : '最大化',
              iconSize: _maximized ? 12 : 14,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _TitleBtn(
              icon: Icons.close_rounded,
              tooltip: '关闭',
              hoverColor: const Color(0xFFE81123),
              hoverFg: Colors.white,
              onTap: () => windowManager.close(), // preventClose → 托盘
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBtn extends StatefulWidget {
  const _TitleBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.iconSize = 16,
    this.hoverColor,
    this.hoverFg,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final double iconSize;
  final Color? hoverColor;
  final Color? hoverFg;

  @override
  State<_TitleBtn> createState() => _TitleBtnState();
}

class _TitleBtnState extends State<_TitleBtn> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final bg = _hover
        ? (widget.hoverColor ?? c.primarySoft.withValues(alpha: 0.7))
        : Colors.transparent;
    final fg = _hover
        ? (widget.hoverFg ?? c.textPrimary)
        : c.textSecondary;

    final btn = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 46,
          height: DesktopTitleBar.height,
          color: bg,
          alignment: Alignment.center,
          child: Icon(widget.icon, size: widget.iconSize, color: fg),
        ),
      ),
    );

    if (widget.tooltip == null) return btn;
    return Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 400), child: btn);
  }
}
