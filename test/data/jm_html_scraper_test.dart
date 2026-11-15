import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/sources/jm_html_scraper.dart';

import '../helpers/fixtures.dart';

void main() {
  group('JmHtmlScraper（首页 HTML 兜底）', () {
    test('解析轮播 / 分节 / 去重网格', () {
      final feed = const JmHtmlScraper().parseHome(Fixtures.text('home.html'));
      expect(feed, isNotNull);
      expect(feed!.banners.length, 2);
      expect(feed.modules.length, 2);
      expect(feed.modules.first.title, '最新上架');
      expect(feed.modules.first.items.length, 2);
      // 轮播 2 条 + 分节 3 条，合并去重后 5 条
      expect(feed.grid.length, 5);
      expect(feed.partialErrors, isNotEmpty);
    });

    test('无专辑锚点时返回 null（交由上层报错）', () {
      expect(const JmHtmlScraper().parseHome('<html><body>空</body></html>'), isNull);
    });
  });
}
