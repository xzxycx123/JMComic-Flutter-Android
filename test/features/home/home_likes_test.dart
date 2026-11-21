import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/home/home_likes.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/sources/jm_likes_scraper.dart';
import 'package:jm_comic/features/home/home_page.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_env.dart';

/// 官方网页列表卡片的真实标记：`<span id="albim_likes_<id>">355</span>`。
///
/// 首页网格来自 `/categories/filter` fixture（1490702/1490703/1490704），
/// 横滑分节来自 `/promote` fixture（1485385…）。
const String _homeHtml = '''
<html><body>
<div class="item"><a href="/album/1490702/x/"><span id="albim_likes_1490702">42</span></a></div>
<div class="item"><a href="/album/1490703/x/"><span id="albim_likes_1490703" class="num">7</span></a></div>
<div class="item"><a href="/album/1485385/x/"><span id="albim_likes_1485385">
  1234
</span></a></div>
</body></html>
''';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  group('JmLikesScraper.parse', () {
    test('解析 albim_likes_* 计数', () {
      final likes = JmLikesScraper.parse(_homeHtml);
      expect(likes['1490702'], 42);
      expect(likes['1490703'], 7);
      expect(likes['1485385'], 1234);
    });

    test('兜底正则：中间夹图标也能解析', () {
      const html = '<a id="albim_likes_1490702"><i class="fa"></i>355</a>';
      expect(JmLikesScraper.parse(html)['1490702'], 355);
    });

    test('没有喜欢数标记 / 乱码返回空', () {
      expect(JmLikesScraper.parse('<html>error</html>'), isEmpty);
      expect(JmLikesScraper.parse(''), isEmpty);
      expect(
        JmLikesScraper.parse('<span id="albim_likes_1">abc</span>'),
        isEmpty,
      );
    });
  });

  group('网页线路', () {
    test('国内优先、国外兜底，域名来自常量', () {
      final candidates = AlbumLikesNotifier.webCandidates;
      expect(candidates, isNotEmpty);
      expect(candidates.first.domestic, isTrue);
      expect(candidates.any((candidate) => !candidate.domestic), isTrue);
    });

    test('列表页地址带分页与排序', () {
      final uri = JmLikesScraper.listUri(
        '18comic.ink',
        page: 2,
        order: 'mr',
      );
      expect(uri.toString(), 'https://18comic.ink/albums?page=2&o=mr');
    });

    test('搜索页地址带关键词与分页（URL 编码）', () {
      final uri = JmLikesScraper.searchUri(
        '18comic.ink',
        query: '同人',
        page: 3,
      );
      expect(uri.path, '/search/photos');
      expect(uri.queryParameters['search_query'], '同人');
      expect(uri.queryParameters['page'], '3');
    });
  });

  group('withScrapedLikes', () {
    const album = JmAlbumSummary(id: '7', title: 'A');

    test('抓到正数就覆盖，0 / 缺失保持原样（显示 --）', () {
      expect(withScrapedLikes(album, {'7': 42}).likes, 42);
      expect(withScrapedLikes(album, {'7': 0}).likes, 0);
      expect(withScrapedLikes(album, {}).likes, 0);
      expect(withScrapedLikes(album, {}).displayLikes, '--');
    });
  });

  testWidgets('首页卡片用网页抓到的喜欢数渲染', (tester) async {
    final requested = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: FakeJmApi()),
          ),
          // 不打真实网络：返回官方网页同款标记。
          albumLikesHtmlProvider.overrideWithValue((Uri uri) async {
            requested.add(uri);
            return _homeHtml;
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    expect(requested, isNotEmpty);
    expect(requested.first.host, 'comic18j-susu.com');
    expect(requested.first.path, '/albums');
    expect(requested.first.queryParameters['page'], '1');

    // 横滑分节里的 1485385（首屏就构建）拿到 1234。
    expect(find.text('1234'), findsWidgets);

    // 网格在折叠线以下：滚到网格后，fixture 首条 1490702 显示 42。
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    expect(find.text('42'), findsWidgets);
  });
}
