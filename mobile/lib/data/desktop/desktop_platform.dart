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
const double kIslandHoverWidth = 320;
const double kIslandHoverHeight = 46;
const double kIslandCardWidth = 352;
const double kIslandCardHeightEmpty = 156;
const double kIslandCardHeightList = 268;
/// 通知播报：同悬停胶囊样式，略宽、略高。
const double kIslandAnnounceWidth = 372;
const double kIslandAnnounceHeight = 50;
/// 播报展示总时长（溢出才滚 + 停留）。
const int kIslandAnnounceSeconds = 10;

/// 关窗后岛 HWND 必须贴内容，透明余量会在系统层挡住其它窗口点击。
const double kIslandWindowStripWidth = 132;
const double kIslandWindowStripHeight = 22;
const double kIslandWindowHoverWidth = 336;
const double kIslandWindowHoverHeight = 58;
const double kIslandWindowAnnounceWidth = 388;
const double kIslandWindowAnnounceHeight = 62;
const double kIslandWindowCardWidth = 380;
const double kIslandWindowCardHeight = 300;

/// 兼容旧命名（默认细条画布）。
const double kIslandWindowWidth = kIslandWindowStripWidth;
const double kIslandWindowHeight = kIslandWindowStripHeight;

const double kIslandTopGap = 0;

/// 岛形态 UI 形变时长（展开略长、收起略短，手感更跟手）。
const int kIslandExpandMs = 340;
const int kIslandCollapseMs = 280;
const int kIslandCardExpandMs = 380;
const int kIslandCardCollapseMs = 300;
/// HWND 在 UI 收起动画结束后再缩，避免裁切。
const int kIslandHwndShrinkDelayMs = 300;

/// 兼容旧命名。
const double kIslandCapsuleWidth = kIslandHoverWidth;
const double kIslandCapsuleHeight = kIslandHoverHeight;
const double kIslandExpandedWidth = kIslandCardWidth;
const double kIslandExpandedHeight = kIslandCardHeightList;

/// 逻辑像素对齐到整数，减轻高分屏错位。
double islandSnap(double v) => v.roundToDouble();
