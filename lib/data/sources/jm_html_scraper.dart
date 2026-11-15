import 'package:dio/dio.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/constants/jm_constants.dart';
import '../../core/utils/logger.dart';
import '../models/home_feed.dart';
import '../models/jm_album_summary.dart';
import '../models/jm_category.dart';
import '../models/jm_promote_module.dart';
import '../models/json_field.dart';

/// 首页 HTML 兜底（PLAN §6.3）。
///
/// 仅在 API 全线路失败时启用；选择器集中在本文件常量区，
/// 改动必须同步 `test/fixtures/home.html` 的断言。
class JmHtmlScraper {
  const JmHtmlScraper();

  static const String carouselSelector = '#index-carousel a[href*="/album/"]';
  static const String moduleSelector = 'div.list-group';
  static const String moduleTitleSelector = 'p.list-group-title';
  static const String moduleItemSelector = 'div.list-group-item a[href*="/album/"]';
  static const String coverSelector = 'img';
  static const String titleSelector = 'div.video-title';

  /// 直接抓首页 HTML 并解析。
  Future<HomeFeed?> fetch(Dio dio, String apiHost) async {
    if (apiHost.trim().isEmpty) return null;
    try {
      final response = await dio.get<String>(
        'https://$apiHost/',
        options: Options(
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'User-Agent': JmConstants.userAgent,
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      );
      final text = response.data ?? '';
      if (!text.contains('<html')) return null;
      return parseHome(text);
    } catch (error) {
      Log.w('HTML 兜底抓取失败：$error');
      return null;
    }
  }

  /// 解析首页 HTML -> [HomeFeed]（categories 留空，由调用方补兜底表）。
  HomeFeed? parseHome(String htmlText) {
    final document = html_parser.parse(htmlText);
    final banners = <PromoteBanner>[];
    for (final anchor in document.querySelectorAll(carouselSelector)) {
      final album = _albumFromAnchor(anchor);
      if (album == null) continue;
      banners.add(PromoteBanner(album: album, moduleTitle: album.categoryTitle));
      if (banners.length >= 6) break;
    }

    final modules = <JmPromoteModule>[];
    for (final group in document.querySelectorAll(moduleSelector)) {
      final title = group.querySelector(moduleTitleSelector)?.text.trim() ?? '';
      final items = <JmAlbumSummary>[];
      for (final anchor in group.querySelectorAll(moduleItemSelector)) {
        final album = _albumFromAnchor(anchor);
        if (album == null) continue;
        if (items.any((item) => item.id == album.id)) continue;
        items.add(album);
      }
      if (items.isEmpty) continue;
      modules.add(
        JmPromoteModule(
          id: '',
          title: title.isEmpty ? '推荐' : title,
          type: 'html',
          filterVal: '',
          items: items,
        ),
      );
    }

    if (banners.isEmpty && modules.isEmpty) return null;

    final flattened = <JmAlbumSummary>[
      ...banners.map((banner) => banner.album),
      ...modules.expand((module) => module.items),
    ];
    final unique = <String, JmAlbumSummary>{};
    for (final album in flattened) {
      unique.putIfAbsent(album.id, () => album);
    }
    final all = unique.values.toList(growable: false);

    return HomeFeed(
      banners: banners,
      modules: modules,
      latest: all.take(40).toList(growable: false),
      grid: all,
      categories: const <JmCategory>[],
      gridPage: 1,
      gridTotal: all.length,
      updatedAt: DateTime.now(),
      partialErrors: const <String>['接口不可用，当前为网页解析结果'],
    );
  }

  JmAlbumSummary? _albumFromAnchor(dom.Element anchor) {
    final href = anchor.attributes['href'] ?? '';
    final match = RegExp(r'/album/(\d+)').firstMatch(href);
    if (match == null) return null;
    final id = match.group(1) ?? '';
    if (id.isEmpty) return null;

    final image = anchor.querySelector(coverSelector);
    final title = anchor.querySelector(titleSelector)?.text.trim() ??
        asString(image?.attributes['alt']) ??
        '';
    // 封面地址在 API 里恒为空；HTML 兜底时自带绝对 URL，但统一由 CoverImage 按 §5.6 拼，
    // 避免两套 URL 规则打架，所以这里只保留 id。
    return JmAlbumSummary(
      id: id,
      title: title.trim(),
      categoryTitle: '',
      updateAt: 0,
      addDate: '',
    );
  }
}
