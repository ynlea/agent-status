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
const double kDesktopDefaultWidth = 1100;
const double kDesktopDefaultHeight = 720;
const double kDesktopMinWidth = 880;
const double kDesktopMinHeight = 600;

/// 灵动岛胶囊默认尺寸。
const double kIslandCapsuleWidth = 320;
const double kIslandCapsuleHeight = 48;
const double kIslandExpandedWidth = 420;
const double kIslandExpandedHeight = 88;
