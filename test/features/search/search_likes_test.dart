import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/repositories/search_repository.dart';
import 'package:jm_comic/features/home/home_likes.dart';
import 'package:jm_comic/features/search/search_page.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_env.dart';

class _MemorySearchHistory extends Fake implements SearchHistoryStore {
  final List<String> _terms = <String>[];

  @override
  List<String> read() => List<String>.of(_terms);

  @override
  Future<List<String>> push(String keyword, {int limit = 10}) async {
    _terms.remove(keyword);
    _terms.insert(0, keyword);
    return read();
  }

  @override
  Future<void> remove(String keyword) async => _terms.remove(keyword);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  testWidgets('搜索结果卡片用 JmAPI 的点赞量渲染', (tester) async {
    final api = FakeJmApi()
      ..likesByAlbum.addAll(<String, int>{'1490702': 42, '1490703': 7});
    final history = _MemorySearchHistory();
    final requested = <String>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          searchHistoryStoreProvider.overrideWithValue(history),
          searchRepositoryProvider.overrideWith(
            (ref) async => SearchRepository(api: api, history: history),
          ),
          albumLikesFetcherProvider.overrideWithValue((String id) async {
            requested.add(id);
            return api.likesByAlbum[id] ?? 0;
          }),
        ],
        child: const MaterialApp(
          home: SearchPage(initialQuery: '测试'),
        ),
      ),
    );
    for (var index = 0; index < 12; index++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // 只对搜索结果里出现的本子取数（不再去抓网页搜索页）。
    expect(requested, containsAll(<String>['1490702', '1490703']));
    expect(find.text('42'), findsWidgets);
  });
}
