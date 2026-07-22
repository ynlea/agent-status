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
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: c.border.withValues(alpha: 0.8),
            ),
            Expanded(child: widget.navigationShell),
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
      width: 88,
      color: c.card,
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
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
                  const SizedBox(height: 8),
                  Text(
                    '轻芽',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _SideRailItem(
              asset: QingyaAssets.navHomeV2,
              label: '首页',
              selected: index == 0,
              color: accents[0],
              onTap: () => onTap(0),
            ),
            _SideRailItem(
              asset: QingyaAssets.navDevicesV2,
              label: '设备',
              selected: index == 1,
              color: accents[1],
              onTap: () => onTap(1),
            ),
            _SideRailIconItem(
              icon: Icons.insights_rounded,
              label: '用量',
              selected: index == 2,
              color: accents[2],
              onTap: () => onTap(2),
            ),
            _SideRailItem(
              asset: QingyaAssets.navSettingsV2,
              label: '设置',
              selected: index == 3,
              color: accents[3],
              onTap: () => onTap(3),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                '桌面',
                style: TextStyle(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRailItem extends StatelessWidget {
  const _SideRailItem({
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
    final effective = selected ? color : c.navInactive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border(
                      left: BorderSide(color: color, width: 3),
                    ),
                  )
                : null,
            child: Column(
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(effective, BlendMode.srcIn),
                  child: Image.asset(asset, width: 22, height: 22),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: effective,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRailIconItem extends StatelessWidget {
  const _SideRailIconItem({
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
    final effective = selected ? color : c.navInactive;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Material(
        color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border(
                      left: BorderSide(color: color, width: 3),
                    ),
                  )
                : null,
            child: Column(
              children: [
                Icon(icon, size: 22, color: effective),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: effective,
                  ),
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
