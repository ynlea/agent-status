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

/// 灵动岛视觉尺寸：细条命中区 = 视觉区（避免“靠近就展开”）。
const double kIslandStripWidth = 120;
const double kIslandStripHeight = 12;
const double kIslandHoverWidth = 292;
const double kIslandHoverHeight = 46;
const double kIslandCardWidth = 352;
const double kIslandCardHeightEmpty = 156;
const double kIslandCardHeightList = 268;
const double kIslandAnnounceHeight = 92;
/// 播报展示总时长（滚动 + 停留）。
const int kIslandAnnounceSeconds = 10;

/// 关窗后岛形态画布：默认够 hover；卡片/播报再一次性放大。
const double kIslandWindowWidth = 320;
const double kIslandWindowHeight = 72;
const double kIslandWindowCardWidth = 380;
const double kIslandWindowCardHeight = 300;

const double kIslandTopGap = 0;

/// 兼容旧命名。
const double kIslandCapsuleWidth = kIslandHoverWidth;
const double kIslandCapsuleHeight = kIslandHoverHeight;
const double kIslandExpandedWidth = kIslandCardWidth;
const double kIslandExpandedHeight = kIslandCardHeightList;

/// 逻辑像素对齐到整数，减轻高分屏错位。
double islandSnap(double v) => v.roundToDouble();
