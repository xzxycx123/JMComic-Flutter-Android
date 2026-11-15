import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/app.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/shell/glass_nav_bar.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 6}) async {
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

  testWidgets('Dock 三档切换 + 各 tab 独立栈', (tester) async {
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

    // 第三档：下载（Dock 外层有 16 的水平内缩，按比例取三档中心）
    await tester.tapAt(Offset(barRect.left + barRect.width * 0.82, barRect.center.dy));
    await _pumpFrames(tester);
    expect(find.text('加入队列'), findsOneWidget);

    // 第二档：我的
    await tester.tapAt(Offset(barRect.left + barRect.width * 0.5, barRect.center.dy));
    await _pumpFrames(tester);
    expect(find.text('未登录 · 本地模式'), findsOneWidget);

    // 回到第一档：首页
    await tester.tapAt(Offset(barRect.left + barRect.width * 0.18, barRect.center.dy));
    await _pumpFrames(tester);
    expect(find.text('JMComic'), findsWidgets);
  });
}
