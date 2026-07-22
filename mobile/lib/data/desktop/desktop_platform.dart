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

/// 灵动岛：贴顶细条 / 悬停胶囊 / 展开卡片。
const double kIslandStripWidth = 96;
const double kIslandStripHeight = 12;
const double kIslandHoverWidth = 300;
const double kIslandHoverHeight = 48;
const double kIslandCardWidth = 360;
const double kIslandCardHeightEmpty = 168;
const double kIslandCardHeightList = 280;
const double kIslandTopGap = 6;

/// 兼容旧命名（避免遗漏引用）。
const double kIslandCapsuleWidth = kIslandHoverWidth;
const double kIslandCapsuleHeight = kIslandHoverHeight;
const double kIslandExpandedWidth = kIslandCardWidth;
const double kIslandExpandedHeight = kIslandCardHeightList;
