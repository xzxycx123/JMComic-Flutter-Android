import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/app.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/shell/glass_nav_bar.dart';

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

  test('Dock 只有两档：首页 / 我的', () {
    expect(GlassNavBar.items.length, 2);
    expect(GlassNavBar.items.map((item) => item.label).toList(), <String>['首页', '我的']);
  });

  testWidgets('Dock 两档切换 + 「我的」二级菜单进入下载与历史', (tester) async {
    final prefs = await testPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: FakeJmApi()),
          ),
        ],
        child: const JmComicApp(),
      ),
    );
    await _pumpFrames(tester);

    expect(find.byType(GlassNavBar), findsOneWidget);
    final barRect = tester.getRect(find.byType(GlassNavBar));

    // 第二档：我的（两项均分，右半区即「我的」）
    await tester.tapAt(Offset(barRect.left + barRect.width * 0.75, barRect.center.dy));
    await _pumpFrames(tester);
    expect(find.text('未登录 · 本地模式'), findsOneWidget);
    expect(find.text('下载与历史'), findsOneWidget);

    // 二级菜单：历史记录（空态）
    await tester.tap(find.text('历史记录').first);
    await _pumpFrames(tester, frames: 12);
    expect(find.text('还没有下载记录'), findsOneWidget);

    // 返回「我的」，再进下载
    await tester.tap(find.byTooltip('返回'));
    await _pumpFrames(tester, frames: 12);
    expect(find.text('未登录 · 本地模式'), findsOneWidget);
    await tester.tap(find.text('下载').first);
    await _pumpFrames(tester, frames: 12);
    expect(find.text('加入队列'), findsOneWidget);

    // 回「我的」再切回首页
    await tester.tap(find.byTooltip('返回'));
    await _pumpFrames(tester, frames: 12);
    await tester.tapAt(Offset(barRect.left + barRect.width * 0.25, barRect.center.dy));
    await _pumpFrames(tester, frames: 12);
    expect(find.text('JMComic'), findsWidgets);
  });
}
