@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/sources/jm_likes_scraper.dart';

/// 实网用例：官方网页「喜歡」数抓取（默认跳过，CI 不跑）。
///
/// ```powershell
/// flutter test --dart-define=JM_LIVE=true test/manual/likes_live_test.dart
/// ```
///
/// 实测（2026-11-21）：`18comic.ink/albums?page=1` 与 APP `o=mr` 第 1 页
/// 80 本重合 63~69 本；搜索页 `/search/photos` 同样带 80 条计数。
const bool _live = bool.fromEnvironment('JM_LIVE');

void main() {
  test(
    '实网：官方网页列表页能解析喜欢数',
    () async {
      const scraper = JmLikesScraper();
      final html = await scraper.fetch(
        JmLikesScraper.listUri('18comic.ink', page: 1, order: 'mr'),
      );
      expect(html, isNotNull);
      final likes = JmLikesScraper.parse(html!);
      // ignore: avoid_print
      print('list pairs=${likes.length}');
      expect(likes.length, greaterThan(10));
    },
    skip: _live ? false : '默认跳过；用 --dart-define=JM_LIVE=true 开启',
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    '实网：官方网页搜索页能解析喜欢数',
    () async {
      const scraper = JmLikesScraper();
      final html = await scraper.fetch(
        JmLikesScraper.searchUri('18comic.ink', query: '同人', page: 2),
      );
      expect(html, isNotNull);
      final likes = JmLikesScraper.parse(html!);
      // ignore: avoid_print
      print('search pairs=${likes.length}');
      expect(likes.length, greaterThan(10));
    },
    skip: _live ? false : '默认跳过；用 --dart-define=JM_LIVE=true 开启',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
