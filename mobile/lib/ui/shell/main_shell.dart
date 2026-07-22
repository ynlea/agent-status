import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/desktop/desktop_platform.dart';
import '../../data/repo/status_repository.dart';
import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(statusRepositoryProvider.notifier).softRefresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final index = widget.navigationShell.currentIndex;
    final accents = [c.primary, c.device, c.working, c.primary];

    if (isQingyaDesktop) {
      return Scaffold(
        backgroundColor: c.scaffold,
        body: Row(
          children: [
            _DesktopSideRail(
              index: index,
              accents: accents,
              onTap: _onTap,
            ),
            Expanded(
              child: Padding(
                // 给顶栏灵动岛留一点空间，内容区也更透气
                padding: const EdgeInsets.fromLTRB(0, 4, 10, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.scaffold,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      bottomLeft: Radius.circular(22),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      bottomLeft: Radius.circular(22),
                    ),
                    child: widget.navigationShell,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.scaffold,
      body: widget.navigationShell,
      bottomNavigationBar: ColoredBox(
        color: c.scaffold,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Container(
            height: 68,
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.border.withValues(alpha: 0.7)),
              boxShadow: [
                BoxShadow(
                  color: c.shadow,
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  asset: QingyaAssets.navHomeV2,
                  label: '首页',
                  selected: index == 0,
                  color: accents[0],
                  onTap: () => _onTap(0),
                ),
                _NavItem(
                  asset: QingyaAssets.navDevicesV2,
                  label: '设备',
                  selected: index == 1,
                  color: accents[1],
                  onTap: () => _onTap(1),
                ),
                _NavIconItem(
                  icon: Icons.insights_rounded,
                  label: '用量',
                  selected: index == 2,
                  color: accents[2],
                  onTap: () => _onTap(2),
                ),
                _NavItem(
                  asset: QingyaAssets.navSettingsV2,
                  label: '设置',
                  selected: index == 3,
                  color: accents[3],
                  onTap: () => _onTap(3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 暖色圆角侧栏：横排图标+文案，选中为柔和胶囊，贴近手机端气质。
class _DesktopSideRail extends StatelessWidget {
  const _DesktopSideRail({
    required this.index,
    required this.accents,
    required this.onTap,
  });

  final int index;
  final List<Color> accents;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    return Container(
      width: 196,
      margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.border.withValues(alpha: 0.85)),
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset(
                    QingyaAssets.catBrandAvatarV3,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '轻芽',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Q I N G Y A',
                        style: TextStyle(
                          fontSize: 8,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          color: c.textSecondary,
                          letterSpacing: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: Container(
              height: 1,
              color: c.divider.withValues(alpha: 0.9),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                _SideNavTile(
                  asset: QingyaAssets.navHomeV2,
                  label: '首页',
                  selected: index == 0,
                  color: accents[0],
                  onTap: () => onTap(0),
                ),
                _SideNavTile(
                  asset: QingyaAssets.navDevicesV2,
                  label: '设备',
                  selected: index == 1,
                  color: accents[1],
                  onTap: () => onTap(1),
                ),
                _SideNavIconTile(
                  icon: Icons.insights_rounded,
                  label: '用量',
                  selected: index == 2,
                  color: accents[2],
                  onTap: () => onTap(2),
                ),
                _SideNavTile(
                  asset: QingyaAssets.navSettingsV2,
                  label: '设置',
                  selected: index == 3,
                  color: accents[3],
                  onTap: () => onTap(3),
                ),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: c.primarySoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Image.asset(
                    QingyaAssets.catHeroWinkV3,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '状态一眼就懂～',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavTile extends StatelessWidget {
  const _SideNavTile({
    required this.asset,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final fg = selected ? color : c.navInactive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
                  child: Image.asset(asset, width: 20, height: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.textPrimary : c.textSecondary,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideNavIconTile extends StatelessWidget {
  const _SideNavIconTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final fg = selected ? color : c.navInactive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c.textPrimary : c.textSecondary,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.asset,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String asset;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effective = selected ? color : context.qingya.navInactive;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ColorFiltered(
              colorFilter: ColorFilter.mode(effective, BlendMode.srcIn),
              child: Image.asset(asset, width: 25, height: 25),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: effective,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIconItem extends StatelessWidget {
  const _NavIconItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final effective = selected ? color : context.qingya.navInactive;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: effective),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: effective,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
