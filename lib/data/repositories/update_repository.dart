import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../models/app_version.dart';
import '../models/release_info.dart';
import '../sources/app_platform_channel.dart';
import '../sources/github_release_client.dart';

/// 自动更新的数据面：查版本 -> 下载 APK -> 交给系统安装器。
///
/// 只做「取数据 + 落盘 + 拉起」，弹窗与开关都在 UI 层，方便两套主题复用。
class UpdateRepository {
  UpdateRepository({
    required GithubReleaseClient client,
    required AppPlatformChannel channel,
    required Dio downloadDio,
  })  : _client = client,
        _channel = channel,
        _dio = downloadDio;

  final GithubReleaseClient _client;
  final AppPlatformChannel _channel;
  final Dio _dio;

  AppVersion? _installed;

  /// 已安装版本（还没读过时回落到 `AppConfig.appVersion`）。
  AppVersion get installedVersion =>
      _installed ??
      AppVersion.tryParse(AppConfig.appVersion) ??
      AppVersion.unknown;

  /// 已安装版本：优先读 PackageManager，读不到回落到 `AppConfig.appVersion`。
  Future<AppVersion> resolveInstalledVersion({bool force = false}) async {
    final cached = _installed;
    if (!force && cached != null && cached.isKnown) return cached;
    final name = await _channel.versionName();
    final parsed = AppVersion.tryParse(name) ??
        AppVersion.tryParse(AppConfig.appVersion) ??
        AppVersion.unknown;
    _installed = parsed;
    return parsed;
  }

  Future<List<ReleaseInfo>> releases() => _client.fetchReleases();

  /// 比当前版本新的最高版本；没有返回 null。
  Future<ReleaseInfo?> findNewerThan(AppVersion current) =>
      _client.fetchNewerThan(current);

  /// 解析出可下载的 APK 附件。
  ///
  /// REST API 自带 `assets`；走 atom 兜底时再读一次 assets 面板补直链。
  /// 都拿不到返回 null（UI 退回「打开发布页」）。
  Future<ReleaseAsset?> resolveApk(ReleaseInfo release) async {
    if (release.apk != null) return release.apk;
    try {
      return await _client.fetchApkAsset(release);
    } catch (_) {
      return null;
    }
  }

  /// 下载 APK 到临时目录，返回本地路径。
  ///
  /// [onProgress] 的 `total` 可能为 -1（GitHub 的 302 重定向偶尔不带长度），
  /// UI 侧按「不确定进度」处理即可。不传 [asset] 时自动解析一次。
  Future<String> downloadApk(
    ReleaseInfo release, {
    ReleaseAsset? asset,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    final resolved = asset ?? await resolveApk(release);
    if (resolved == null) {
      throw const ReleaseDownloadException('该版本没有 APK 附件');
    }
    final dir = await _updateDir();
    final file = File(
      '${dir.path}${Platform.pathSeparator}${_fileName(release, resolved)}',
    );
    if (file.existsSync()) {
      // 上次中断留下的半截包直接重下，别让安装器报「解析包错误」。
      try {
        file.deleteSync();
      } catch (_) {
        // 删不掉就覆盖写，dio 会截断原文件。
      }
    }
    try {
      await _dio.download(
        resolved.downloadUrl,
        file.path,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, dynamic>{'Accept': 'application/octet-stream'},
        ),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const ReleaseDownloadException('已取消下载');
      }
      throw ReleaseDownloadException('下载失败：${_reason(error)}');
    }
    if (!file.existsSync() || file.lengthSync() <= 0) {
      throw const ReleaseDownloadException('下载失败：文件为空');
    }
    return file.path;
  }

  /// 拉起系统安装器（Android 需要「安装未知来源应用」权限）。
  Future<bool> installApk(String path) async {
    final result = await OpenFilex.open(path);
    return result.type == ResultType.done;
  }

  /// 兜底入口：用浏览器打开 release 页（没有 APK 附件 / 安装器拉不起来时）。
  Future<bool> openReleasePage(ReleaseInfo release) =>
      _channel.openUrl(release.htmlUrl);

  /// 清掉上次下载的安装包（设置页「清理临时文件」也可以顺手调用）。
  Future<void> clearDownloads() async {
    try {
      final dir = await _updateDir();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {
      // 临时目录清理失败不影响主流程。
    }
  }

  Future<Directory> _updateDir() async {
    final cache = await getTemporaryDirectory();
    final dir = Directory('${cache.path}${Platform.pathSeparator}jm-update');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 文件名只留 ASCII 安全字符：`JMComic-0.4.4-release.apk`。
  String _fileName(ReleaseInfo release, ReleaseAsset asset) {
    final raw = asset.name.isEmpty
        ? 'JMComic-${release.version.plain}.apk'
        : asset.name;
    final cleaned = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (cleaned.toLowerCase().endsWith('.apk')) return cleaned;
    return '$cleaned.apk';
  }

  static String _reason(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return '连接 GitHub 超时，换个网络再试';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return code == null ? '服务端返回异常' : 'HTTP $code';
      default:
        return error.message ?? '网络异常';
    }
  }
}

class ReleaseDownloadException implements Exception {
  const ReleaseDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
