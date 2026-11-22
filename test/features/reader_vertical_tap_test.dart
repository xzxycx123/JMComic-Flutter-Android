import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/repositories/album_repository.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/reader_page.dart';
import 'package:jm_comic/features/reader/reader_providers.dart';
import 'package:jm_comic/features/reader/widgets/reader_hud.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';
import 'package:jm_comic/features/reader/widgets/scroll_reader_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

const ReaderArgs _args = ReaderArgs(
  albumId: '7000',
  chapterId: '7999',
  title: '第 1 话',
  albumTitle: '测试本',
);

ReaderData _data(ReaderMode mode) => ReaderData(
      args: _args,
      chapter: const JmChapter(
        id: '7999',
        title: '第 1 话',
        images: <String>['001.webp', '002.webp', '003.webp'],
      ),
      scrambleId: 220980,
      initialPage: 1,
      mode: mode,
    );

class _StubReaderController extends ReaderController {
  _StubReaderController(this.data);

  final ReaderData data;

  @override
  Future<ReaderData> build(ReaderArgs arg) async => data;
}

/// 取页桩：每页都是「80 × 600」的竖图，一屏正好一页，方便断言整屏位移。
class _StubAlbumRepository extends AlbumRepository {
  _StubAlbumRepository(JmApi api, ProgressStore store)
      : super(api: api, progress: store);

  @override
  Future<Uint8List?> loadPage({
    required String photoId,
    required String filename,
    int? scrambleIdOverride,
  }) async =>
      syntheticPng(width: 80, height: 600);
}

class _MemoryProgressStore extends ProgressStore {
  _MemoryProgressStore(super.box);

  final Map<String, ReaderProgress> _values = <String, ReaderProgress>{};

  @override
  ReaderProgress? read(String albumId, String chapterId) =>
      _values[ProgressStore.keyFor(albumId, chapterId)];

  @override
  Future<void> write(
    String albumId,
    String chapterId,
    ReaderProgress progress,
  ) async {
    _values[ProgressStore.keyFor(albumId, chapterId)] = progress;
    notifyChanged();
  }
}

class _MemorySettingsStore extends SettingsStore {
  _MemorySettingsStore(super.box);

  AppSettings _value = const AppSettings();

  @override
  AppSettings read() => _value;

  @override
  Future<void> write(AppSettings settings) async => _value = settings;
}

Future<void> _pumpReader(
  WidgetTester tester, {
  required ReaderMode mode,
}) async {
  final store =
      _MemoryProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress));
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(await testPreferences()),
      settingsStoreProvider.overrideWithValue(
        _MemorySettingsStore(Hive.box<dynamic>(HiveBoxes.settings)),
      ),
      jmApiProvider.overrideWithValue(FakeJmApi()),
      progressStoreProvider.overrideWithValue(store),
      albumRepositoryProvider.overrideWith(
        (ref) async => _StubAlbumRepository(FakeJmApi(), store),
      ),
      readerDataProvider.overrideWith(() => _StubReaderController(_data(mode))),
    ],
  );
  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/home',
    routes: <RouteBase>[
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => router.push('/reader'),
              child: const Text('打开阅读器'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/reader',
        builder: (context, state) => const ReaderPage(args: _args),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('打开阅读器'));
  await tester.pumpAndSettle();
}

/// 让 `Image.memory` 的解码在 fake-async 里真正完成（竖读靠图片真实高度撑开列表）。
Future<void> _settleImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

ScrollPosition _position(WidgetTester tester) => tester
    .widget<ScrollReaderView>(find.byType(ScrollReaderView))
    .controller
    .position;

/// 点一下（竖读外层有双击缩放识别器，单击要等 300ms 的双击判定）。
Future<void> _tapAt(WidgetTester tester, double ratio) async {
  final rect = tester.getRect(find.byType(ScrollReaderView));
  await tester.tapAt(Offset(rect.left + rect.width * ratio, rect.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// 跑完 HUD 计时器并退出阅读器，避免残留 Timer / Overlay。
Future<void> _drain(WidgetTester tester) async {
  unawaited(tester.binding.handlePopRoute());
  await tester.pump();
  await tester.pump(const Duration(seconds: 4));
  await tester.pump(const Duration(seconds: 4));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  group('readerTapZoneAt（三分区落点）', () {
    test('左 30% 向前、中 40% 详情、右 30% 向后', () {
      expect(readerTapZoneAt(0, 360), ReaderTapZone.previous);
      expect(readerTapZoneAt(107, 360), ReaderTapZone.previous);
      expect(readerTapZoneAt(108, 360), ReaderTapZone.hud, reason: '边界归中间');
      expect(readerTapZoneAt(180, 360), ReaderTapZone.hud);
      expect(readerTapZoneAt(252, 360), ReaderTapZone.hud, reason: '边界归中间');
      expect(readerTapZoneAt(253, 360), ReaderTapZone.next);
      expect(readerTapZoneAt(359, 360), ReaderTapZone.next);
    });

    test('宽度未知时不做翻页，退回详情区', () {
      expect(readerTapZoneAt(10, 0), ReaderTapZone.hud);
      expect(readerTapZoneAt(10, -1), ReaderTapZone.hud);
    });
  });

  group('竖读三分区点击', () {
    testWidgets('点右翻下一屏、点左回上一屏、点中间切 HUD', (tester) async {
      await _pumpReader(tester, mode: ReaderMode.vertical);
      await _settleImages(tester);

      final position = _position(tester);
      final screen = position.viewportDimension;
      expect(screen, greaterThan(0));
      expect(position.pixels, 0);

      await _tapAt(tester, .9); // 右 1/3 → 下一屏
      expect(position.pixels, closeTo(screen, .5), reason: '整屏前进一屏');

      await _tapAt(tester, .9);
      expect(position.pixels, closeTo(screen * 2, .5));

      await _tapAt(tester, .1); // 左 1/3 → 上一屏
      expect(position.pixels, closeTo(screen, .5));

      // 中间 40% 仍然是「显示详情」。
      ReaderHud hud() => tester.widget<ReaderHud>(find.byType(ReaderHud));
      final before = hud().visible;
      await _tapAt(tester, .5);
      expect(hud().visible, !before, reason: '中间点击切换 HUD');

      await _drain(tester);
    });

    testWidgets('顶部点左不会滚出上边界', (tester) async {
      await _pumpReader(tester, mode: ReaderMode.vertical);
      await _settleImages(tester);

      final position = _position(tester);
      expect(position.pixels, 0);

      await _tapAt(tester, .1);
      expect(position.pixels, 0, reason: '已经在最上面，点左只是回弹');

      await _drain(tester);
    });

    testWidgets('竖读不叠点击层：结束页 / 图片上的按钮仍然拿得到点击', (tester) async {
      await _pumpReader(tester, mode: ReaderMode.vertical);
      await _settleImages(tester);

      // 竖读用外层 onTapUp 判定落点，不往滚动视图上叠 ReaderTapZones，
      // 否则叠层会先赢手势竞技场，结束页上的按钮就点不动了。
      expect(find.byType(ReaderTapZones), findsNothing);

      await _drain(tester);
    });
  });
}
