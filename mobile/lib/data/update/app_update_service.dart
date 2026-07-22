import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// GitHub Release 检查 / 下载 / 调起系统安装。
class AppUpdateService {
  AppUpdateService({
    http.Client? client,
    this.repoOwner = 'ynlea',
    this.repoName = 'agent-status',
    this.apkAssetName = 'qingya-android-release.apk',
    this.windowsSetupAssetName = 'qingya-windows-setup.exe',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String repoOwner;
  final String repoName;
  final String apkAssetName;
  final String windowsSetupAssetName;

  static const _installChannel = MethodChannel('qingya/updater');

  /// 当前平台期望的安装包资产名。
  String get platformAssetName {
    if (Platform.isAndroid) return apkAssetName;
    if (Platform.isWindows) return windowsSetupAssetName;
    return apkAssetName;
  }

  Uri get _latestUri => Uri.https(
        'api.github.com',
        '/repos/$repoOwner/$repoName/releases/latest',
      );

  Map<String, String> get _headers => {
        'Accept': 'application/vnd.github+json',
        'User-Agent': Platform.isWindows ? 'qingya-windows' : 'qingya-android',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// 查询 latest；[currentVersion] 为 package_info 的 version（不含 v）。
  Future<AppUpdateCheckResult> checkLatest(String currentVersion) async {
    final res = await _client
        .get(_latestUri, headers: _headers)
        .timeout(const Duration(seconds: 20));
    if (res.statusCode == 404) {
      return AppUpdateCheckResult.failure('暂无公开 Release');
    }
    if (res.statusCode != 200) {
      return AppUpdateCheckResult.failure(
        '检查失败（HTTP ${res.statusCode}）',
      );
    }
    final body = jsonDecode(res.body);
    if (body is! Map<String, dynamic>) {
      return AppUpdateCheckResult.failure('Release 数据格式异常');
    }
    final tag = '${body['tag_name'] ?? ''}'.trim();
    if (tag.isEmpty) {
      return AppUpdateCheckResult.failure('Release 缺少版本号');
    }
    final remote = normalizeVersion(tag);
    final local = normalizeVersion(currentVersion);
    if (remote.isEmpty) {
      return AppUpdateCheckResult.failure('无法解析版本 $tag');
    }

    final want = platformAssetName;
    String? assetUrl;
    final assets = body['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is! Map) continue;
        final name = '${a['name'] ?? ''}';
        if (name == want) {
          final url = '${a['browser_download_url'] ?? ''}'.trim();
          if (url.isNotEmpty) assetUrl = url;
          break;
        }
      }
    }
    final notes = '${body['body'] ?? ''}'.trim();
    final newer = compareSemver(remote, local) > 0;
    return AppUpdateCheckResult(
      ok: true,
      hasUpdate: newer,
      tag: tag.startsWith('v') || tag.startsWith('V') ? tag : 'v$tag',
      remoteVersion: remote,
      localVersion: local.isEmpty ? currentVersion : local,
      apkUrl: assetUrl,
      releaseNotes: notes,
      message: newer
          ? (assetUrl == null ? '发现新版本，但未找到安装包' : null)
          : '已是最新版本',
    );
  }

  /// 下载安装包，[onProgress] 为 0~1（未知总长时为 null 进度用 received 字节）。
  Future<File> downloadApk({
    required String url,
    required String tag,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final req = http.Request('GET', Uri.parse(url));
    req.headers.addAll(_headers);
    final streamed = await _client.send(req).timeout(const Duration(seconds: 30));
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw AppUpdateException('下载失败（HTTP ${streamed.statusCode}）');
    }
    final rawTotal = streamed.contentLength;
    final total = (rawTotal != null && rawTotal > 0) ? rawTotal : null;
    final dir = await getTemporaryDirectory();
    final outDir = Directory('${dir.path}/updates');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final safeTag = tag.replaceAll(RegExp(r'[^0-9A-Za-z._-]'), '_');
    final ext = Platform.isWindows ? 'exe' : 'apk';
    final file = File('${outDir.path}/qingya-$safeTag.$ext');
    if (await file.exists()) {
      await file.delete();
    }
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in streamed.stream) {
        if (isCancelled?.call() == true) {
          throw AppUpdateException('已取消下载');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
    } catch (e) {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
    await sink.close();
    if (received <= 0) {
      throw AppUpdateException('下载文件为空');
    }
    return file;
  }

  /// 安装：Android 走 MethodChannel；Windows 调起 setup.exe。
  Future<void> installApk(String path) async {
    if (Platform.isWindows) {
      await installWindowsSetup(path);
      return;
    }
    if (!Platform.isAndroid) {
      throw AppUpdateException('当前平台不支持应用内安装');
    }
    try {
      await _installChannel.invokeMethod<void>('installApk', {'path': path});
    } on PlatformException catch (e) {
      throw AppUpdateException(e.message ?? e.code);
    }
  }

  /// 调起 Windows 安装程序（Inno Setup 等生成的 setup.exe）。
  Future<void> installWindowsSetup(String path) async {
    if (!Platform.isWindows) {
      throw AppUpdateException('仅支持 Windows 安装');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw AppUpdateException('安装包不存在');
    }
    try {
      await Process.start(
        path,
        const [],
        mode: ProcessStartMode.detached,
      );
    } catch (e) {
      throw AppUpdateException('无法打开安装程序：$e');
    }
  }

  /// 去掉 v 前缀，只保留数字段用 `.` 连接的主体。
  static String normalizeVersion(String raw) {
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1);
    }
    // 去掉 +build 与预发布后缀的前置处理：1.2.3-beta → 1.2.3
    final plus = s.indexOf('+');
    if (plus >= 0) s = s.substring(0, plus);
    final dash = s.indexOf('-');
    if (dash >= 0) s = s.substring(0, dash);
    return s.trim();
  }

  /// a>b → 1；a==b → 0；a<b → -1
  static int compareSemver(String a, String b) {
    List<int> parts(String v) {
      if (v.isEmpty) return const [0];
      return v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    }

    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.ok,
    this.hasUpdate = false,
    this.tag = '',
    this.remoteVersion = '',
    this.localVersion = '',
    this.apkUrl,
    this.releaseNotes = '',
    this.message,
  });

  factory AppUpdateCheckResult.failure(String message) => AppUpdateCheckResult(
        ok: false,
        message: message,
      );

  final bool ok;
  final bool hasUpdate;
  final String tag;
  final String remoteVersion;
  final String localVersion;
  /// 下载地址（历史字段名 apkUrl；Windows 下为 setup.exe URL）。
  final String? apkUrl;
  final String releaseNotes;
  final String? message;
}

class AppUpdateException implements Exception {
  AppUpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}
