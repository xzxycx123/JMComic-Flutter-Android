import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/repositories/search_repository.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  group('resolveSearchQuery（本地判定）', () {
    test('纯车号 / JM 前缀 / 链接 → album', () {
      for (final input in <String>[
        '350234',
        'JM350234',
        '/album/350234/',
        '?id=350234',
      ]) {
        final decision = resolveSearchQuery(input);
        expect(decision.isAlbum, isTrue, reason: input);
        expect(decision.albumId, '350234', reason: input);
      }
    });

    test('关键词 → keyword', () {
      final decision = resolveSearchQuery('中文');
      expect(decision.isKeyword, isTrue);
      expect(decision.keyword, '中文');
      expect(decision.hint.contains('回车搜索'), isTrue);
    });

    test('显式关键词模式保留纯数字与 JM 形态', () {
      for (final input in ['350234', 'JM350234']) {
        final decision = resolveSearchQuery(input, forceKeyword: true);
        expect(decision.isKeyword, isTrue);
        expect(decision.keyword, input);
      }
    });

    test('空输入 → empty（不发请求）', () {
      expect(resolveSearchQuery('   ').isEmpty, isTrue);
      expect(resolveSearchQuery('').hint, '输入车号或关键词');
    });
  });

  group('SearchRepository', () {
    late SearchRepository repository;

    setUp(() {
      repository = SearchRepository(
        api: FakeJmApi(),
        history: SearchHistoryStore(Hive.box<dynamic>(HiveBoxes.searchHistory)),
      );
    });

    test('关键词搜索返回分页结果', () async {
      final page = await repository.search(keyword: '中文');
      expect(page.content.length, 3);
      expect(page.total, 10000);
      expect(page.query, '中文');
    });

    test('历史记录去重置顶且保留顺序', () async {
      await repository.remember('中文');
      await repository.remember('同人');
      await repository.remember('中文');
      expect(repository.history, <String>['中文', '同人']);
      await repository.clearHistory();
      expect(repository.history, isEmpty);
    });

    test('逐条移除历史只删除指定条目并保持顺序', () async {
      final box = Hive.box<dynamic>(HiveBoxes.searchHistory);
      final store = SearchHistoryStore(box);
      await store.push('第一条');
      await store.push('第二条');
      await store.push('第三条');
      await store.remove('第二条');
      expect(SearchHistoryStore(box).read(), ['第三条', '第一条']);
    });

    test('纯车号不请求搜索也能拿到 redirect', () async {
      expect(await repository.resolveRedirect('350234'), '350234');
    });
  });
}
