import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  group('HomeRepository', () {
    test('聚合四类区块', () async {
      final repository = HomeRepository(api: FakeJmApi());
      final feed = await repository.fetchFeed();

      expect(feed.modules.length, 2);
      expect(feed.banners.length, 2);
      expect(feed.latest.length, 4);
      expect(feed.grid.length, 3);
      expect(feed.categories.length, 10);
      expect(feed.gridTotal, 10000);
      expect(feed.gridTotalCapped, isTrue);
      expect(feed.updatedAt, isNotNull);
      expect(feed.partialErrors, isEmpty);
    });

    test('readCachedFeed 不依赖 JmApi，可直接恢复上次首页', () async {
      final feed = await HomeRepository(api: FakeJmApi()).fetchFeed();
      final box = Hive.box<dynamic>(HiveBoxes.feedCache);
      await box.put('feed', <String, dynamic>{
        'payload': feed.encode(),
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final cached = HomeRepository.readCachedFeed(box);
      expect(cached, isNotNull);
      expect(cached!.fromCache, isTrue);
      expect(cached.grid.length, feed.grid.length);
      expect(cached.categories.length, feed.categories.length);
      expect(cached.updatedAt, isNotNull);
      await box.clear();
    });
    test('mergeUnique 按 id 去重保序', () {
      const a = JmAlbumSummary(id: '1', title: 'a');
      const b = JmAlbumSummary(id: '2', title: 'b');
      const a2 = JmAlbumSummary(id: '1', title: 'a-again');
      final merged = HomeRepository.mergeUnique(
        <JmAlbumSummary>[a, b],
        <JmAlbumSummary>[a2],
      );
      expect(merged.map((item) => item.id).toList(), <String>['1', '2']);
      expect(merged.first.title, 'a');
    });

    test('分类接口为空时用 10 个固定分类兜底', () async {
      final repository = HomeRepository(api: FakeJmApi(emptyCategories: true));
      final feed = await repository.fetchFeed();
      expect(feed.categories.length, JmCategoryFallback.items.length);
    });

    test('loadMore 页码递增且不产生重复项', () async {
      final repository = HomeRepository(api: FakeJmApi());
      final feed = await repository.fetchFeed();
      final next = await repository.loadMore(feed);
      expect(next.gridPage, 2);
      expect(next.grid.length, feed.grid.length);
    });

    test('服务端返回空页 → gridExhausted，再翻不再发请求', () async {
      final api = FakeJmApi(emptyAfterFirstPage: true);
      final repository = HomeRepository(api: api);
      final feed = await repository.fetchFeed();
      expect(feed.gridExhausted, isFalse);

      final ended = await repository.loadMore(feed);
      expect(ended.gridExhausted, isTrue);
      final calls = api.filterCalls;

      final again = await repository.loadMore(ended);
      expect(again.gridPage, ended.gridPage);
      expect(api.filterCalls, calls, reason: '到底后不应再请求 /categories/filter');
    });

    test('全部端点失败且无缓存时抛出可读异常', () async {
      final repository = HomeRepository(api: FakeJmApi(failAll: true));
      expect(
        () => repository.fetchFeed(),
        throwsA(isA<Exception>()),
      );
    });

    test('分类筛选按 slug 请求，且不污染首页磁盘缓存', () async {
      final box = Hive.box<dynamic>(HiveBoxes.feedCache);
      await box.clear();
      final api = FakeJmApi();
      final repository = HomeRepository(api: api, cacheBox: box);

      final filtered = await repository.fetchFeed(
        categorySlug: 'doujin',
        order: AlbumOrder.mostViewed,
      );
      expect(api.lastCategorySlug, 'doujin', reason: 'c 必须传 slug，不能传数字 id');
      expect(api.lastFilterOrder, AlbumOrder.mostViewed);
      expect(filtered.grid.length, 1);
      expect(filtered.grid.single.categoryId, '1');
      expect(box.get('feed'), isNull, reason: '分类页不写首页缓存');

      final latest = await repository.fetchFeed();
      expect(api.lastCategorySlug, isEmpty);
      expect(latest.grid.length, 3);
      expect(box.get('feed'), isNotNull);
      await box.clear();
    });

    test('分页沿用 slug：第二页仍带同一分类', () async {
      final api = FakeJmApi();
      final repository = HomeRepository(api: api);
      final feed = await repository.fetchFeed(categorySlug: 'single');
      expect(feed.grid.length, 2);
      expect(feed.grid.every((album) => album.categoryId == '2'), isTrue);

      await repository.loadMore(feed, categorySlug: 'single');
      expect(api.filterQueries.last.slug, 'single');
      expect(api.filterQueries.last.page, 2);
    });
  });
}
