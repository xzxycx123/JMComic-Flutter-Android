import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/home/home_page.dart';
import 'package:jm_comic/features/home/widgets/album_card.dart';
import 'package:jm_comic/features/home/widgets/hero_banner.dart';
import 'package:jm_comic/features/home/widgets/section_header.dart';
import 'package:jm_comic/features/home/widgets/category_chips.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 8}) async {
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

  testWidgets('首页渲染轮播 / 分类条 / 分节 / 网格', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
          // 不接 Hive 缓存：widget 测试的 fake-async 环境里 Hive 的异步写不会推进。
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: FakeJmApi()),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(HeroBanner), findsOneWidget);
    expect(find.byType(CategoryChips), findsOneWidget);
    expect(find.byType(SectionHeader), findsWidgets);
    // 网格首屏 3 张（横滑分节在折叠线以下，ListView.builder 懒加载不构建）
    expect(find.byType(AlbumCard), findsAtLeastNWidgets(3));
    // 轮播首条标题来自 promote fixture
    expect(find.textContaining('轉生到不認識的世界'), findsWidgets);
  });

  testWidgets('分类条渲染 10 个顶层分类', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
          // 不接 Hive 缓存：widget 测试的 fake-async 环境里 Hive 的异步写不会推进。
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: FakeJmApi()),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('最新A漫'), findsOneWidget);
    expect(find.text('同人'), findsWidgets);
    expect(find.text('English Manga'), findsOneWidget);
  });

  testWidgets('点「同人」用 slug 重查，轮播/分节收起，网格只剩同人', (tester) async {
    final api = FakeJmApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: api),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(HeroBanner), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(CategoryChips),
        matching: find.text('同人'),
      ),
    );
    await _pumpFrames(tester);

    // `/categories/filter?c=doujin`：数字 id 会被服务端忽略，所以这里必须是 slug。
    expect(
      api.filterQueries.where((query) => query.slug == 'doujin'),
      isNotEmpty,
    );
    // 筛选态：全局轮播 / 推荐分节隐藏，避免「看着没变」。
    expect(find.byType(HeroBanner), findsNothing);
    // 网格只剩同人那一本（fixture 里 1490702）。
    expect(find.text('瀑布流測試條目 B'), findsNothing);
    expect(find.textContaining('子供を甘く見るな'), findsWidgets);
  });

  testWidgets('筛选结果为空时给空态而不是白屏', (tester) async {
    final api = FakeJmApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: api),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(CategoryChips),
        matching: find.text('韓漫'),
      ),
    );
    await _pumpFrames(tester);

    expect(api.filterQueries.any((query) => query.slug == 'hanman'), isTrue);
    expect(find.textContaining('暂无内容'), findsOneWidget);
  });

  testWidgets('二级分类按 父slug_子slug 重查', (tester) async {
    final api = FakeJmApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: api),
          ),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    await tester.tap(
      find.descendant(
        of: find.byType(CategoryChips),
        matching: find.text('同人'),
      ),
    );
    await _pumpFrames(tester);

    // 二级条只在带 sub_categories 的分类下出现。
    expect(find.byType(SubCategoryChips), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(SubCategoryChips),
        matching: find.text('漢化'),
      ),
    );
    await _pumpFrames(tester);

    expect(
      api.filterQueries.any((query) => query.slug == 'doujin_chinese'),
      isTrue,
      reason: '二级筛选要用 父slug_子slug，不是 sub.CID',
    );
  });
}
