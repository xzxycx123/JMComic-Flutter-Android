import 'dart:convert';
import 'dart:io';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/logger.dart';

/// 官方网页「喜歡」数抓取（数据层）。
///
/// APP 列表接口（`/promote`、`/latest`、`/categories/filter`、`/search`）只给
/// `liked` 布尔，没有计数；只有 `/album?id=` 带 likes（一本一次请求）。
/// 官方网页的列表页每张卡片都带计数：
/// `<span id="albim_likes_1490702">355</span>`，一页 80 本，正好对应一页 feed。
///
/// 国内 / 国外是不同的网页域名（见 [JmConstants.domesticHosts] /
/// [JmConstants.overseasWebHosts]），线路选择交给调用方。
class JmLikesScraper {
  const JmLikesScraper();

  static final RegExp _pair = RegExp(r'id="albim_likes_(\d+)"[^>]*>\s*(\d+)');

  /// 宽松兜底：`id` 与数字之间可能夹 `<i>` 图标或换行。
  static final RegExp _loose =
      RegExp(r'albim_likes_(\d+)"[^>]*>[^0-9]{0,32}(\d+)');

  /// 页面里是否有喜欢数标记（有才值得解析）。
  static bool looksLikeLikes(String html) => html.contains('albim_likes_');

  /// HTML -> `{albumId: likes}`（负数 / 乱码丢弃；同 id 后出现的覆盖前面的）。
  static Map<String, int> parse(String html) {
    if (!looksLikeLikes(html)) return const <String, int>{};
    final result = <String, int>{};
    for (final pattern in <RegExp>[_pair, _loose]) {
      for (final match in pattern.allMatches(html)) {
        final id = match.group(1);
        final likes = int.tryParse(match.group(2) ?? '');
        if (id == null || id.isEmpty || likes == null || likes < 0) continue;
        result[id] = likes;
      }
      if (result.isNotEmpty) break;
    }
    return result;
  }

  /// 首页 / 分类 / 排序列表页：`https://host/albums?page=N&o=<排序>`。
  ///
  /// [order] 直接用 APP 的 `AlbumOrder.code`（`mr` / `mv_t` …）。
  static Uri listUri(
    String host, {
    required int page,
    String order = '',
    String category = '0',
  }) {
    final query = <String>['page=${page < 1 ? 1 : page}'];
    if (order.isNotEmpty) query.add('o=$order');
    if (category.isNotEmpty && category != '0') query.add('c=$category');
    return Uri.parse('https://$host/albums?${query.join('&')}');
  }

  /// 搜索页：`https://host/search/photos?search_query=<q>&page=N`。
  static Uri searchUri(
    String host, {
    required String query,
    required int page,
    String order = '',
  }) {
    final params = <String>[
      'search_query=${Uri.encodeQueryComponent(query)}',
      'page=${page < 1 ? 1 : page}',
      if (order.isNotEmpty) 'o=$order',
    ];
    return Uri.parse('https://$host/search/photos?${params.join('&')}');
  }

  /// 拉一页网页 HTML；非 200 / 没有喜欢数标记时返回 null（调用方换线路）。
  Future<String?> fetch(
    Uri uri, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = JmConstants.userAgent;
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'text/html');
      final response = await request.close().timeout(timeout);
      if (response.statusCode != HttpStatus.ok) return null;
      final text =
          await response.transform(utf8.decoder).join().timeout(timeout);
      return looksLikeLikes(text) ? text : null;
    } catch (error) {
      Log.d('喜欢数网页抓取失败 $uri：$error');
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
