import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/qingya_theme.dart';
import '../widgets/assets.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onTap(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.qingya;
    final index = navigationShell.currentIndex;
    final accents = [c.primary, c.device, c.working, c.primary];
    return Scaffold(
      backgroundColor: c.scaffold,
      body: navigationShell,
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
