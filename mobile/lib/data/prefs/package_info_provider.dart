import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 读取 pubspec 中的 version / build number，与安装包一致。
final packageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});

extension PackageInfoLabel on PackageInfo {
  /// 例如 v0.1.6
  String get versionLabel => 'v$version';

  /// 例如 v0.1.6 (6)
  String get versionWithBuild => 'v$version ($buildNumber)';
}
