import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/utils/logger.dart';
import '../models/app_version.dart';
import '../models/release_info.dart';
import '../models/release_notes.dart';

/// 拉取 GitHub Release 失败（两路都挂了才会抛）。
class ReleaseFetchException implements Exception {
  const ReleaseFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 读 https://github.com/{owner}/{repo}/releases 上的发布信息。
///
/// 两路取数，按顺序尝试：
/// 1. REST API（`/releases`）：有 Markdown 正文和 APK 附件，但未鉴权时限流很紧；
/// 2. `releases.atom`：GitHub 不设限流，正文是 HTML（渲染成同一套 block），
///    但拿不到附件信息 —— 只用于「有新版本 / 看更新说明」。
///
/// 只挑「版本号解析得出来、不是预发布」的 release；`draft` 一律忽略。
class GithubReleaseClient {
  GithubReleaseClient({
    Dio? dio,
    this.owner = AppConfig.releaseOwner,
    this.repo = AppConfig.releaseRepo,
    this.perPage = 30,
  }) : _dio = dio ?? _defaultDio();

  final Dio _dio;
  final String owner;
  final String repo;
  final int perPage;

  String get _apiUrl => 'https://api.github.com/repos/$owner/$repo/releases';
  String get _atomUrl => 'https://github.com/$owner/$repo/releases.atom';

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
          headers: <String, dynamic>{
            'Accept': 'application/vnd.github+json, application/atom+xml;q=0.9',
            'User-Agent':
                '${AppConfig.appName}-Android/${AppConfig.appVersion}',
          },
        ),
      );

  /// 全部可用的 release（新的在前）。API 失败时自动退回 atom。
  Future<List<ReleaseInfo>> fetchReleases() async {
    Object? apiError;
    try {
      final releases = await _fetchFromApi();
      if (releases.isNotEmpty) return releases;
    } catch (error) {
      apiError = error;
      Log.i('GitHub API 取 release 失败，改用 atom：$error');
    }
    try {
      final releases = await _fetchFromAtom();
      if (releases.isNotEmpty) return releases;
    } catch (error) {
      throw ReleaseFetchException(
        apiError == null ? '读取发布页失败：$error' : '读取发布页失败：$apiError / $error',
      );
    }
    return const <ReleaseInfo>[];
  }

  /// 比 [current] 新的最高版本；没有就返回 null。
  Future<ReleaseInfo?> fetchNewerThan(AppVersion current) async {
    final releases = await fetchReleases();
    return pickNewest(releases, current);
  }

  /// 从一堆 release 里挑出版本号最高的那个（纯函数，单测直接调）。
  static ReleaseInfo? pickNewest(
    List<ReleaseInfo> releases,
    AppVersion current,
  ) {
    ReleaseInfo? newest;
    for (final release in releases) {
      if (release.prerelease || !release.version.isKnown) continue;
      if (!release.version.isNewerThan(current)) continue;
      if (newest == null || release.version.isNewerThan(newest.version)) {
        newest = release;
      }
    }
    return newest;
  }

  // -------------------------------------------------------------- REST API
  Future<List<ReleaseInfo>> _fetchFromApi() async {
    final response = await _dio.get<String>(
      _apiUrl,
      queryParameters: <String, dynamic>{'per_page': '$perPage'},
      options: Options(
        headers: <String, dynamic>{
          'Accept': 'application/vnd.github+json',
        },
        responseType: ResponseType.plain,
        receiveTimeout: const Duration(seconds: 20),
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ReleaseFetchException('GitHub API HTTP $status');
    }
    final body = response.data ?? '';
    final decoded = jsonDecode(body);
    if (decoded is! List) {
      throw const ReleaseFetchException('GitHub API 返回格式异常');
    }
    final releases = <ReleaseInfo>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final release = _fromApiItem(item.cast<String, dynamic>());
      if (release != null) releases.add(release);
    }
    return releases;
  }

  ReleaseInfo? _fromApiItem(Map<String, dynamic> json) {
    if (json['draft'] == true) return null;
    final tag = (json['tag_name'] as String?)?.trim() ?? '';
    final version = AppVersion.tryParse(tag);
    if (version == null) return null;
    final name = (json['name'] as String?)?.trim() ?? '';
    final body = (json['body'] as String?) ?? '';
    final htmlUrl = (json['html_url'] as String?)?.trim() ?? '';
    final published = DateTime.tryParse(
      (json['published_at'] as String?) ??
          (json['created_at'] as String?) ??
          '',
    );
    return ReleaseInfo(
      tag: tag,
      version: version,
      title: name.isEmpty ? tag : name,
      notes: ReleaseNotes.markdown(body),
      htmlUrl:
          htmlUrl.isEmpty ? '${AppConfig.releasesPageUrl}/tag/$tag' : htmlUrl,
      apk: _pickApk(json['assets']),
      publishedAt: published,
      prerelease: json['prerelease'] == true || version.prerelease,
    );
  }

  ReleaseAsset? _pickApk(Object? assets) {
    if (assets is! List) return null;
    ReleaseAsset? fallback;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final map = asset.cast<String, dynamic>();
      final name = (map['name'] as String?)?.trim() ?? '';
      final url = (map['browser_download_url'] as String?)?.trim() ?? '';
      if (name.isEmpty || url.isEmpty) continue;
      final lower = name.toLowerCase();
      if (!lower.endsWith('.apk')) {
        if (fallback == null && lower.contains('apk')) {
          fallback = ReleaseAsset(
            name: name,
            downloadUrl: url,
            sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
          );
        }
        continue;
      }
      return ReleaseAsset(
        name: name,
        downloadUrl: url,
        sizeBytes: (map['size'] as num?)?.toInt() ?? 0,
      );
    }
    return fallback;
  }

  // ---------------------------------------------------------------- 兜底 atom
  Future<List<ReleaseInfo>> _fetchFromAtom() async {
    final response = await _dio.get<String>(
      _atomUrl,
      options: Options(
        headers: <String, dynamic>{'Accept': 'application/atom+xml'},
        responseType: ResponseType.plain,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ReleaseFetchException('releases.atom HTTP $status');
    }
    return parseAtom(response.data ?? '');
  }

  /// atom 兜底拿不到附件信息时，按 tag 再读一次 assets 面板补出 APK 直链。
  ///
  /// GitHub 的 release 页附件列表是懒加载的：`/releases/expanded_assets/<tag>`
  /// 直接返回一小段 HTML，里面就是 `releases/download/.../*.apk` 的链接。
  Future<ReleaseAsset?> fetchApkAsset(ReleaseInfo release) async {
    if (release.apk != null) return release.apk;
    final url = 'https://github.com/$owner/$repo/releases/expanded_assets/'
        '${Uri.encodeComponent(release.tag)}';
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: <String, dynamic>{'Accept': 'text/html'},
        responseType: ResponseType.plain,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw ReleaseFetchException('assets 面板 HTTP $status');
    }
    return parseAssetsPage(response.data ?? '');
  }

  /// 从 assets 面板 HTML 里取出第一个 APK 直链（纯函数，单测直接喂样例）。
  static ReleaseAsset? parseAssetsPage(String html) {
    final match = RegExp(
      r'href="(/?[^"]*/releases/download/[^"]+?\.apk)"',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;
    final href = match.group(1)!.replaceAll('&amp;', '&');
    final url = href.startsWith('http')
        ? href
        : 'https://github.com${href.startsWith('/') ? '' : '/'}$href';
    final segments = Uri.parse(url).pathSegments;
    return ReleaseAsset(
      name: segments.isEmpty ? 'update.apk' : segments.last,
      downloadUrl: url,
    );
  }

  /// 解析 releases.atom（纯函数，单测直接喂样例）。
  static List<ReleaseInfo> parseAtom(String xml) {
    final releases = <ReleaseInfo>[];
    final entries = RegExp(r'<entry>([\s\S]*?)</entry>').allMatches(xml);
    for (final entry in entries) {
      final block = entry.group(1) ?? '';
      final link = RegExp(
        r'<link[^>]*rel="alternate"[^>]*href="([^"]+)"',
      ).firstMatch(block);
      final htmlUrl = link?.group(1) ?? '';
      var tag = _tagFromUrl(htmlUrl);
      tag ??= RegExp(r'<id>[^<]*/([^</]+)</id>').firstMatch(block)?.group(1);
      if (tag == null || tag.isEmpty) continue;
      final version = AppVersion.tryParse(tag);
      if (version == null) continue;
      final title = _unescapeXml(
        RegExp(r'<title>([\s\S]*?)</title>').firstMatch(block)?.group(1) ?? '',
      );
      final rawContent = RegExp(r'<content[^>]*>([\s\S]*?)</content>')
              .firstMatch(block)
              ?.group(1) ??
          '';
      final updated = DateTime.tryParse(
        RegExp(r'<updated>([^<]+)</updated>').firstMatch(block)?.group(1) ?? '',
      );
      releases.add(
        ReleaseInfo(
          tag: tag,
          version: version,
          title: title.isEmpty ? tag : title,
          notes: ReleaseNotes.html(_unescapeXml(rawContent)),
          htmlUrl: htmlUrl.isEmpty
              ? '${AppConfig.releasesPageUrl}/tag/$tag'
              : htmlUrl,
          publishedAt: updated,
          prerelease: version.prerelease,
        ),
      );
    }
    return releases;
  }

  static String? _tagFromUrl(String url) {    final match = RegExp(r'/releases/tag/([^/?#]+)').firstMatch(url);
    if (match == null) return null;
    return Uri.decodeComponent(match.group(1)!);
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
