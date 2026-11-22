import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/models/jm_album_meta.dart';
import 'package:jm_comic/data/repositories/search_repository.dart';
import 'package:jm_comic/features/home/home_likes.dart';
import 'package:jm_comic/features/search/search_page.dart';
import 'package:jm_comic/features/search/widgets/result_grid.dart';

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

  testWidgets('向下滚动收起搜索框与排序条，向上滚动恢复', (tester) async {
    tester.view.physicalSize = const Size(400, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = FakeJmApi();
    final history = _MemorySearchHistory();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          searchHistoryStoreProvider.overrideWithValue(history),
          searchRepositoryProvider.overrideWith(
            (ref) async => SearchRepository(api: api, history: history),
          ),
          albumMetaFetcherProvider.overrideWithValue((String id) async => const JmAlbumMeta()),
        ],
        child: const MaterialApp(home: SearchPage(initialQuery: '测试')),
      ),
    );

    Future<void> settle() async {
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    await settle();
    expect(find.byType(ResultGrid), findsOneWidget);

    // 结果区顶边初始在搜索框 + 提示 + 结果头 + 排序条之下。
    final expandedTop = tester.getTopLeft(find.byType(ResultGrid)).dy;

    await tester.drag(find.byType(ResultGrid), const Offset(0, -160));
    await settle();
    expect(tester.takeException(), isNull);
    final collapsedTop = tester.getTopLeft(find.byType(ResultGrid)).dy;
    expect(
      collapsedTop,
      lessThan(expandedTop - 60),
      reason: '向下滚动后搜索框与排序条应折叠，结果区上移',
    );

    await tester.drag(find.byType(ResultGrid), const Offset(0, 80));
    await settle();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byType(ResultGrid)).dy,
      closeTo(expandedTop, 1),
      reason: '向上滚动后搜索框与排序条应重新展开',
    );
  });
}
