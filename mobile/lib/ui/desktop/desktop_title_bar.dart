import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/desktop/window_controller.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

/// 自定义标题栏：固定布局，悬停只改颜色不改尺寸。
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
    try {
      final m = await windowManager.isMaximized();
      if (mounted) setState(() => _maximized = m);
    } catch (_) {}
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
      elevation: 0,
      child: Container(
        height: DesktopTitleBar.height,
        decoration: BoxDecoration(
          color: c.card,
          border: Border(
            bottom: BorderSide(color: c.border.withValues(alpha: 0.85)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onPanStart: (_) {
                  unawaited(windowManager.startDragging());
                },
                onDoubleTap: () async {
                  try {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  } catch (_) {}
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.asset(
                          QingyaAssets.catAppIcon,
                          width: 16,
                          height: 16,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                          errorBuilder: (_, __, ___) => Image.asset(
                            QingyaAssets.catBrandAvatarV3,
                            width: 16,
                            height: 16,
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
                          height: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _CaptionButton(
              icon: Icons.remove_rounded,
              // 最小化也收进灵动岛/托盘，不走系统最小化
              onTap: () =>
                  QingyaWindowController.instance.requestHideToBackground(),
            ),
            _CaptionButton(
              // 固定同一套图标字号，避免悬停/最大化切换导致视觉跳动
              icon: _maximized
                  ? Icons.fullscreen_exit_rounded
                  : Icons.crop_square_rounded,
              onTap: () async {
                try {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                } catch (_) {}
              },
            ),
            _CaptionButton(
              icon: Icons.close_rounded,
              isClose: true,
              onTap: () => unawaited(windowManager.close()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final Color bg;
    final Color fg;
    if (_hover) {
      bg = widget.isClose ? const Color(0xFFE81123) : c.primarySoft;
      fg = widget.isClose ? Colors.white : c.textPrimary;
    } else {
      bg = Colors.transparent;
      fg = c.textSecondary;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          width: 46,
          height: DesktopTitleBar.height,
          child: ColoredBox(
            color: bg,
            child: Center(
              child: Icon(
                widget.icon,
                size: 16,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
