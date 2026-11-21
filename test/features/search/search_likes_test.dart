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

const String _searchHtml = '''
<html><body>
<span id="albim_likes_1490702">42</span>
<span id="albim_likes_1490703">7</span>
</body></html>
''';

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

  testWidgets('搜索结果卡片也显示网页抓到的喜欢数', (tester) async {
    final api = FakeJmApi();
    final history = _MemorySearchHistory();
    final requested = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          searchHistoryStoreProvider.overrideWithValue(history),
          searchRepositoryProvider.overrideWith(
            (ref) async => SearchRepository(api: api, history: history),
          ),
          albumLikesHtmlProvider.overrideWithValue((Uri uri) async {
            requested.add(uri);
            return _searchHtml;
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

    // 搜索页去抓的是网页搜索页（不是 /albums）。
    expect(requested, isNotEmpty);
    expect(requested.first.path, '/search/photos');
    expect(requested.first.queryParameters['search_query'], '测试');

    expect(find.text('42'), findsWidgets);
  });
}
