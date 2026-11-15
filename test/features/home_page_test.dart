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
}
