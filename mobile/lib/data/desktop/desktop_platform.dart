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
/// 通知播报：同悬停胶囊样式，略宽；高度保证两行字不被压扁。
const double kIslandAnnounceWidth = 372;
const double kIslandAnnounceHeight = 56;
/// 播报展示总时长（溢出才滚 + 停留）。
const int kIslandAnnounceSeconds = 10;

/// 关窗后岛 HWND 贴内容；左右留白统一 8，保证细条/胶囊水平中心一致。
const double kIslandWindowPad = 8;
const double kIslandWindowStripWidth = kIslandStripWidth + kIslandWindowPad * 2;
const double kIslandWindowStripHeight = kIslandStripHeight + kIslandWindowPad * 2;
const double kIslandWindowHoverWidth = kIslandHoverWidth + kIslandWindowPad * 2;
const double kIslandWindowHoverHeight = kIslandHoverHeight + kIslandWindowPad * 2;
const double kIslandWindowAnnounceWidth =
    kIslandAnnounceWidth + kIslandWindowPad * 2;
const double kIslandWindowAnnounceHeight =
    kIslandAnnounceHeight + kIslandWindowPad * 2;
const double kIslandWindowCardWidth = 380;
const double kIslandWindowCardHeight = 300;

/// 兼容旧命名（默认细条画布）。
const double kIslandWindowWidth = kIslandWindowStripWidth;
const double kIslandWindowHeight = kIslandWindowStripHeight;

const double kIslandTopGap = 0;

/// 岛形态 UI 形变：单一短动画，避免与 HWND 双重动画打架。
const int kIslandExpandMs = 220;
const int kIslandCollapseMs = 180;
const int kIslandCardExpandMs = 260;
const int kIslandCardCollapseMs = 220;
/// HWND 在 UI 收起动画结束后再缩，避免裁切。
const int kIslandHwndShrinkDelayMs = 200;

/// 兼容旧命名。
const double kIslandCapsuleWidth = kIslandHoverWidth;
const double kIslandCapsuleHeight = kIslandHoverHeight;
const double kIslandExpandedWidth = kIslandCardWidth;
const double kIslandExpandedHeight = kIslandCardHeightList;

/// 逻辑像素对齐到整数，减轻高分屏错位。
double islandSnap(double v) => v.roundToDouble();
