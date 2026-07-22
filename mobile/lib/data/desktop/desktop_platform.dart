import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// 产品目标为 Windows 桌面；非桌面平台全部关闭壳层能力。
bool get isQingyaDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows;
}

/// 主从分栏断点：内容区宽度（逻辑像素）。
const double kDesktopMasterDetailBreakpoint = 900;

/// 默认主窗尺寸。
const double kDesktopDefaultWidth = 1180;
const double kDesktopDefaultHeight = 760;
const double kDesktopMinWidth = 920;
const double kDesktopMinHeight = 620;

/// 用量页桌面内容最大宽。
const double kDesktopUsageMaxWidth = 1120;

/// 灵动岛视觉尺寸（在固定透明窗内动画，不再频繁改 HWND 大小）。
const double kIslandStripWidth = 108;
const double kIslandStripHeight = 10;
/// 细条命中热区（视觉仍是细条，避免难悬停）。
const double kIslandStripHitHeight = 28;
const double kIslandHoverWidth = 292;
const double kIslandHoverHeight = 46;
const double kIslandCardWidth = 352;
const double kIslandCardHeightEmpty = 156;
const double kIslandCardHeightList = 268;
const double kIslandAnnounceHeight = 92;

/// 独立岛窗固定画布（足够容纳最大卡片，内容顶中对齐动画）。
const double kIslandWindowWidth = 372;
const double kIslandWindowHeight = 300;

const double kIslandTopGap = 0;

/// 兼容旧命名。
const double kIslandCapsuleWidth = kIslandHoverWidth;
const double kIslandCapsuleHeight = kIslandHoverHeight;
const double kIslandExpandedWidth = kIslandCardWidth;
const double kIslandExpandedHeight = kIslandCardHeightList;

/// 逻辑像素对齐到整数，减轻高分屏错位。
double islandSnap(double v) => v.roundToDouble();
