import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';

import '../helpers/fixtures.dart';

void main() {
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
  });
}
