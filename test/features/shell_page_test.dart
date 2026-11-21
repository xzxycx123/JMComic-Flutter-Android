import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/app.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/router/app_router.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/mine/mine_page.dart';
import 'package:jm_comic/features/shell/glass_nav_bar.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

class _MemorySettingsStore extends Fake implements SettingsStore {
  AppSettings _settings = const AppSettings();

  @override
  AppSettings read() => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
  }
}

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
    expect(
      GlassNavBar.items.map((item) => item.label).toList(),
      <String>['首页', '我的'],
    );
  });

  testWidgets('Dock 两档切换 + 「我的」二级菜单进入下载与历史', (tester) async {
    final prefs = await testPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
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
    await tester
        .tapAt(Offset(barRect.left + barRect.width * 0.75, barRect.center.dy));
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
    await tester
        .tapAt(Offset(barRect.left + barRect.width * 0.25, barRect.center.dy));
    await _pumpFrames(tester, frames: 12);
    expect(find.text('JMComic'), findsWidgets);
  });

  testWidgets('「我的」可切换 LiquidGlass / Metal，Dock 即时更新', (
    tester,
  ) async {
    final prefs = await testPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
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
    final metalRect = tester.getRect(find.byType(GlassNavBar));
    await tester.tapAt(
      Offset(metalRect.left + metalRect.width * 0.75, metalRect.center.dy),
    );
    await _pumpFrames(tester);

    final mineScrollable = find.descendant(
      of: find.byType(MinePage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('LiquidGlass'),
      240,
      scrollable: mineScrollable.first,
    );
    expect(find.text('Metal'), findsOneWidget);
    await tester.ensureVisible(find.text('LiquidGlass'));
    await tester.pump();
    final priorScroll = tester.state<ScrollableState>(mineScrollable.first);
    final priorOffset = priorScroll.position.pixels;
    await tester.tap(find.text('LiquidGlass'));
    await _pumpFrames(tester, frames: 12);

    expect(find.byType(LiquidGlassNavBar), findsOneWidget);
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(find.byType(GlassNavBar), findsNothing);

    final liquidScrollable = find.descendant(
      of: find.byType(MinePage),
      matching: find.byType(Scrollable),
    );
    expect(
      tester.state<ScrollableState>(liquidScrollable.first),
      same(priorScroll),
    );
    expect(priorScroll.position.pixels, closeTo(priorOffset, 1));
    await tester.scrollUntilVisible(
      find.text('Metal'),
      240,
      scrollable: liquidScrollable.first,
    );
    await tester.ensureVisible(find.text('Metal'));
    await tester.pump();
    await tester.tap(find.text('Metal'));
    await _pumpFrames(tester, frames: 12);

    expect(find.byType(GlassNavBar), findsOneWidget);
    expect(find.byType(LiquidGlassNavBar), findsNothing);
  });

  testWidgets('二级路由、输入和根弹层同步切换材质', (tester) async {
    final prefs = await testPreferences();
    final api = FakeJmApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
          downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((_) async => api),
          homeRepositoryProvider
              .overrideWith((_) async => HomeRepository(api: api)),
        ],
        child: const JmComicApp(),
      ),
    );
    await _pumpFrames(tester);
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JmComicApp)));
    final router = container.read(goRouterProvider);
    final settings = container.read(settingsProvider.notifier);
    unawaited(router.push<void>('/search'));
    await _pumpFrames(tester, frames: 12);
    await tester.enterText(find.byType(EditableText), '输入不会丢失');

    final searchContext = tester.element(find.byType(EditableText));
    AppInterfaceStyle? result;
    final resultFuture = showDialog<AppInterfaceStyle>(
      context: searchContext,
      builder: (context) => AlertDialog(
        content: Text(context.interfaceStyle.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(context.interfaceStyle),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    unawaited(resultFuture.then<void>((value) => result = value));
    await _pumpFrames(tester);
    expect(find.text('metal'), findsOneWidget);
    unawaited(settings.setInterfaceStyle(AppInterfaceStyle.liquidGlass));
    await _pumpFrames(tester);
    expect(find.text('liquidGlass'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await _pumpFrames(tester);
    expect(result, AppInterfaceStyle.liquidGlass);
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.controller.text, '输入不会丢失');
    expect(router.canPop(), isTrue);
  });
}
