import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/repositories/album_repository.dart';
import 'package:jm_comic/features/album/album_providers.dart';
import 'package:jm_comic/features/reader/reader_image_saver.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/reader_page.dart';
import 'package:jm_comic/features/reader/reader_providers.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';
import 'package:jm_comic/features/reader/widgets/scroll_reader_view.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

const ReaderArgs _readerArgs = ReaderArgs(
  albumId: '7000',
  chapterId: '7999',
  title: '第 1 话',
  albumTitle: '测试本',
);

ReaderData _readerData({ReaderMode mode = ReaderMode.paged}) => ReaderData(
      args: _readerArgs,
      chapter: const JmChapter(
        id: '7999',
        title: '第 1 话',
        images: <String>['001.webp', '002.webp', '003.webp'],
      ),
      scrambleId: 220980,
      initialPage: 1,
      mode: mode,
    );

/// 阅读器数据直接用桩，不碰网络 / 仓储。
class _StubReaderController extends ReaderController {
  _StubReaderController(this.data);

  final ReaderData data;

  @override
  Future<ReaderData> build(ReaderArgs arg) async => data;
}

/// 页面字节固定失败（不跑图片解码），只关心进度落盘。
class _StubAlbumRepository extends AlbumRepository {
  _StubAlbumRepository(ProgressStore store, {this.bytes})
      : super(api: FakeJmApi(), progress: store);

  /// 非空时 `loadPage` 返回这张图（测试「下载当页图片」用）。
  final Uint8List? bytes;

  @override
  Future<Uint8List?> loadPage({
    required String photoId,
    required String filename,
    int? scrambleIdOverride,
  }) async =>
      bytes;
}

/// 可注入延迟的 store：验证「旧页慢写不会盖掉新页」。
class _SlowProgressStore extends ProgressStore {
  _SlowProgressStore(super.box, {required this.delays});

  final Map<int, Duration> delays;

  @override
  Future<void> write(
    String albumId,
    String chapterId,
    ReaderProgress progress,
  ) async {
    final delay = delays[progress.page];
    if (delay != null) await Future<void>.delayed(delay);
    await super.write(albumId, chapterId, progress);
  }
}

ProgressStore _store() =>
    ProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress));

/// widget 测试用的内存 store：写入只落在内存里。
///
/// Hive 的写盘定时器在 widget 测试的 fake-async 区域里不会触发，
/// 直接等真实 box 会让用例挂死；真实落盘由上面的非 widget 用例覆盖。
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

/// widget 测试用的内存设置 store：避免 Hive 写盘定时器卡在 fake-async 里。
class _MemorySettingsStore extends SettingsStore {
  _MemorySettingsStore(Box<dynamic> box) : super(box);

  AppSettings _value = const AppSettings();

  @override
  AppSettings read() => _value;

  @override
  Future<void> write(AppSettings settings) async => _value = settings;
}

class _Harness {
  _Harness({
    required this.store,
    required this.container,
    required this.router,
  });

  final ProgressStore store;
  final ProviderContainer container;
  final GoRouter router;

  Future<void> flush() async {
    await container.read(readerProgressRecorderProvider).flush();
  }

  ReaderProgress? read([String chapterId = '7999']) =>
      store.read('7000', chapterId);
}

Future<_Harness> _pumpReader(
  WidgetTester tester, {
  ReaderMode mode = ReaderMode.paged,
  Uint8List? pageBytes,
  ReaderImageSaver? imageSaver,
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
      if (imageSaver != null)
        readerImageSaverProvider.overrideWithValue(imageSaver),
      albumRepositoryProvider.overrideWith(
        (ref) async => _StubAlbumRepository(store, bytes: pageBytes),
      ),
      readerDataProvider
          .overrideWith(() => _StubReaderController(_readerData(mode: mode))),
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
        builder: (context, state) => const ReaderPage(args: _readerArgs),
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
  return _Harness(store: store, container: container, router: router);
}

/// 点右侧 1/3 翻到下一页（不带 pumpAndSettle，方便控制时间）。
Future<void> _tapNext(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(ReaderTapZones));
  await tester.tapAt(Offset(rect.left + rect.width * 0.9, rect.center.dy));
  await tester.pump(const Duration(milliseconds: 320));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  group('clampReaderPage', () {
    test('total > 0 时夹在 1..total', () {
      expect(clampReaderPage(0, 10), 1);
      expect(clampReaderPage(-3, 10), 1);
      expect(clampReaderPage(4, 10), 4);
      expect(clampReaderPage(11, 10), 10);
      expect(clampReaderPage(1, 1), 1);
      expect(clampReaderPage(9, 1), 1);
    });

    test('total == 0 安全落到第 1 页', () {
      expect(clampReaderPage(0, 0), 1);
      expect(clampReaderPage(5, 0), 1);
      expect(clampReaderPage(-2, 0), 1);
    });
  });

  group('ProgressStore', () {
    test('写入后 revision 递增并通知监听器，read 回读完整字段', () async {
      final store = _store();
      var notified = 0;
      store.addListener(() => notified++);
      expect(store.revision, 0);

      await store.write(
        '7000',
        '7999',
        const ReaderProgress(
          page: 3,
          total: 9,
          updatedAt: 1234,
          albumTitle: '测试本',
          chapterTitle: '第 1 话',
        ),
      );

      expect(store.revision, 1);
      expect(notified, 1);
      final progress = store.read('7000', '7999')!;
      expect(progress.page, 3);
      expect(progress.total, 9);
      expect(progress.updatedAt, 1234);
      expect(progress.albumTitle, '测试本');
      expect(progress.chapterTitle, '第 1 话');

      await store.remove('7000', '7999');
      expect(store.revision, 2);
      expect(store.read('7000', '7999'), isNull);
    });

    test('多章进度互相独立，历史按 updatedAt 倒序', () async {
      final store = _store();
      await store.write(
        '7000',
        '7999',
        const ReaderProgress(page: 2, total: 5, updatedAt: 1000),
      );
      await store.write(
        '7000',
        '8000',
        const ReaderProgress(page: 5, total: 5, updatedAt: 2000),
      );

      expect(store.read('7000', '7999')!.page, 2);
      expect(store.read('7000', '8000')!.page, 5);
      final entries = store.entries();
      expect(entries, hasLength(2));
      expect(entries.first.chapterId, '8000');
      expect(entries.last.chapterId, '7999');
    });
  });

  group('ProgressRecorder', () {
    test('落盘 albumId / chapterId / page / total / 标题 / updatedAt', () async {
      final store = _store();
      final recorder = ProgressRecorder(
        store: store,
        clock: () => DateTime.fromMillisecondsSinceEpoch(4321),
      );

      await recorder.record(
        const ProgressSnapshot(
          albumId: '7000',
          chapterId: '7999',
          page: 3,
          total: 3,
          albumTitle: '测试本',
          chapterTitle: '第 1 话',
        ),
      );

      final progress = store.read('7000', '7999')!;
      expect(progress.page, 3);
      expect(progress.total, 3);
      expect(progress.updatedAt, 4321);
      expect(progress.albumTitle, '测试本');
      expect(progress.chapterTitle, '第 1 话');
      expect(recorder.writes, 1);
    });

    test('串行化 + 最后一次写入优先：慢的旧页不会盖掉新页', () async {
      final store = _SlowProgressStore(
        Hive.box<dynamic>(HiveBoxes.readerProgress),
        delays: <int, Duration>{1: const Duration(milliseconds: 30)},
      );
      final recorder = ProgressRecorder(store: store);

      final first = recorder.record(
        const ProgressSnapshot(
          albumId: '7000',
          chapterId: '7999',
          page: 1,
          total: 9,
        ),
      );
      final second = recorder.record(
        const ProgressSnapshot(
          albumId: '7000',
          chapterId: '7999',
          page: 4,
          total: 9,
        ),
      );

      await Future.wait(<Future<void>>[first, second]);
      await recorder.flush();

      expect(store.read('7000', '7999')!.page, 4, reason: '旧页不能覆盖新页');
      expect(recorder.writes, 2);
    });

    test('连点时中间快照被合并（只写最新一页）', () async {
      final store = _SlowProgressStore(
        Hive.box<dynamic>(HiveBoxes.readerProgress),
        delays: <int, Duration>{1: const Duration(milliseconds: 30)},
      );
      final recorder = ProgressRecorder(store: store);

      final first = recorder.record(
        const ProgressSnapshot(
          albumId: '7000',
          chapterId: '7999',
          page: 1,
          total: 9,
        ),
      );
      unawaited(
        recorder.record(
          const ProgressSnapshot(
            albumId: '7000',
            chapterId: '7999',
            page: 2,
            total: 9,
          ),
        ),
      );
      final last = recorder.record(
        const ProgressSnapshot(
          albumId: '7000',
          chapterId: '7999',
          page: 3,
          total: 9,
        ),
      );

      await Future.wait(<Future<void>>[first, last]);
      await recorder.flush();

      expect(recorder.writes, 2, reason: '第 1 页在写时，2 被 3 覆盖');
      expect(store.read('7000', '7999')!.page, 3);
    });

    test('缺 album / chapter 的空快照不落盘', () async {
      final store = _store();
      final recorder = ProgressRecorder(store: store);
      await recorder.record(
        const ProgressSnapshot(
          albumId: '',
          chapterId: '7999',
          page: 1,
          total: 1,
        ),
      );
      await recorder.flush();
      expect(recorder.writes, 0);
      expect(store.entries(), isEmpty);
    });

    test('flush 等队列清空后才返回', () async {
      final store = _SlowProgressStore(
        Hive.box<dynamic>(HiveBoxes.readerProgress),
        delays: <int, Duration>{2: const Duration(milliseconds: 20)},
      );
      final recorder = ProgressRecorder(store: store);
      unawaited(
        recorder.record(
          const ProgressSnapshot(
            albumId: '7000',
            chapterId: '7999',
            page: 2,
            total: 9,
          ),
        ),
      );
      expect(recorder.idle, isFalse);
      await recorder.flush();
      expect(recorder.idle, isTrue);
      expect(store.read('7000', '7999')!.page, 2);
    });
  });

  group('chapterProgressProvider 刷新', () {
    test('Hive 落盘后 provider 立刻重算，多章互不干扰', () async {
      final store = _store();
      final container = ProviderContainer(
        overrides: <Override>[progressStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      const args = (albumId: '7000', chapterId: '7999');
      const other = (albumId: '7000', chapterId: '8000');
      expect(container.read(chapterProgressProvider(args)), isNull);

      await store.write(
        '7000',
        '7999',
        const ReaderProgress(page: 4, total: 9, updatedAt: 1),
      );
      expect(container.read(chapterProgressProvider(args))!.page, 4);

      await store.write(
        '7000',
        '8000',
        const ReaderProgress(page: 2, total: 3, updatedAt: 2),
      );
      expect(container.read(chapterProgressProvider(other))!.page, 2);
      expect(container.read(chapterProgressProvider(args))!.page, 4);
    });

    test('阅读器落盘器写入后 provider 也会刷新（revision 生效）', () async {
      final store = _store();
      final container = ProviderContainer(
        overrides: <Override>[progressStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      const args = (albumId: '7000', chapterId: '7999');
      expect(container.read(chapterProgressProvider(args)), isNull);

      await container.read(readerProgressRecorderProvider).record(
            const ProgressSnapshot(
              albumId: '7000',
              chapterId: '7999',
              page: 7,
              total: 9,
            ),
          );
      expect(container.read(chapterProgressProvider(args))!.page, 7);
    });
  });

  group('阅读器退出落盘', () {
    testWidgets('系统返回（PopScope）也会保存当前页', (tester) async {
      final harness = await _pumpReader(tester);
      expect(harness.read(), isNull);

      await _tapNext(tester);
      await harness.flush();

      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
      await harness.flush();

      expect(find.byType(ReaderPage), findsNothing, reason: '返回到上一页');
      final progress = harness.read()!;
      expect(progress.page, 2);
      expect(progress.total, 3);
      expect(progress.albumTitle, '测试本');
      expect(progress.chapterTitle, '第 1 话');
      expect(progress.updatedAt, greaterThan(0));
    });

    testWidgets('HUD 退出会 await 落盘，读到最后一页也保留最后页', (tester) async {
      final harness = await _pumpReader(tester);

      await _tapNext(tester); // -> 2
      await _tapNext(tester); // -> 3（最后一页）

      await tester.tap(find.byType(AppIconButton).first);
      await tester.pumpAndSettle();
      await harness.flush();

      expect(find.byType(ReaderPage), findsNothing);
      final progress = harness.read()!;
      expect(progress.page, 3, reason: '最后一页不自动重置');
      expect(progress.total, 3);
      expect(progress.percent, 100);
    });

    testWidgets('返回详情后 chapterProgressProvider 立即拿到新进度', (tester) async {
      final harness = await _pumpReader(tester);
      const args = (albumId: '7000', chapterId: '7999');
      expect(harness.container.read(chapterProgressProvider(args)), isNull);

      await _tapNext(tester);
      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
      await harness.flush();

      final progress = harness.container.read(chapterProgressProvider(args));
      expect(progress, isNotNull);
      expect(progress!.page, 2);
      expect(progress.total, 3);
    });
  });

  group('竖读整屏缩放', () {
    double zoomOf(WidgetTester tester) {
      final transform = tester.widget<Transform>(
        find
            .ancestor(
              of: find.byType(ScrollReaderView),
              matching: find.byType(Transform),
            )
            .first,
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    Future<void> doubleTapReader(WidgetTester tester) async {
      final center = tester.getRect(find.byType(ScrollReaderView)).center;
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 320));
    }

    testWidgets('双指放大的是整屏漫画，而不是单张页', (tester) async {
      await _pumpReader(tester, mode: ReaderMode.vertical);
      expect(
        find.byType(InteractiveViewer),
        findsNothing,
        reason: '竖读不再逐页缩放',
      );
      expect(zoomOf(tester), 1.0);

      final center = tester.getRect(find.byType(ScrollReaderView)).center;
      final first = await tester.startGesture(center - const Offset(40, 0));
      final second = await tester.startGesture(center + const Offset(40, 0));
      await tester.pump();
      await first.moveBy(const Offset(-80, 0));
      await second.moveBy(const Offset(80, 0));
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pump();

      expect(zoomOf(tester), greaterThan(2.0), reason: '整块阅读区被放大');
      expect(find.byType(ScrollReaderView), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);

      // 收回 1.0 再退出，避免残留缩放与 HUD 定时器。
      await doubleTapReader(tester); // 放大 → 双击收起（此时已放大，双击回 1.0）
      await tester.pumpAndSettle();
      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
    });

    testWidgets('竖读双击切换整屏放大 1.0 ↔ 2.2', (tester) async {
      await _pumpReader(tester, mode: ReaderMode.vertical);
      expect(zoomOf(tester), 1.0);

      await doubleTapReader(tester);
      expect(zoomOf(tester), closeTo(2.2, 0.01));

      await doubleTapReader(tester);
      expect(zoomOf(tester), 1.0);

      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
    });
  });

  group('更多菜单 / 下载当页图片', () {
    Future<void> openMore(WidgetTester tester) async {
      // 顶栏只剩「退出」「更多」两个按钮，更多在最后。
      await tester.tap(find.byType(AppIconButton).last);
      await tester.pumpAndSettle();
    }

    testWidgets('二级菜单含翻页方式 / 选择节点 / 下载当页图片，节点是三级菜单', (tester) async {
      await _pumpReader(tester);

      await openMore(tester);
      expect(find.text('翻页方式'), findsOneWidget);
      expect(find.text('选择节点'), findsOneWidget);
      expect(find.text('下载当页图片'), findsOneWidget);
      // 标题行右侧显示当前模式，副标题是「点击切换到…」提示。
      expect(find.text('左右翻页'), findsOneWidget);

      // 三级菜单：选择节点 → 分流列表。
      await tester.tap(find.text('选择节点'));
      await tester.pumpAndSettle();
      expect(find.text('切换分流'), findsOneWidget);
      expect(find.textContaining('www.cd'), findsWidgets);

      // 返回键先关三级菜单，再退出阅读器。
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('切换分流'), findsNothing);

      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
    });

    testWidgets('「更多」菜单：标题与右侧取值压在同一条中线，副标题另起一行', (tester) async {
      await _pumpReader(tester);
      await openMore(tester);

      final titleY = tester.getCenter(find.text('翻页方式')).dy;
      final valueY = tester.getCenter(find.text('左右翻页')).dy;
      expect(
        valueY,
        moreOrLessEquals(titleY, epsilon: .5),
        reason: '右侧取值与标题同一中线（之前 trailing 会被居中到两行之间）',
      );
      final subtitleY = tester.getCenter(find.text('点击切换到上下滚动')).dy;
      expect(subtitleY, greaterThan(titleY), reason: '副标题另起一行，不再和取值挤在一起');
    });

    testWidgets('二级菜单里切换翻页方式', (tester) async {
      await _pumpReader(tester);

      await openMore(tester);
      await tester.tap(find.text('翻页方式'));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollReaderView), findsOneWidget, reason: '切到上下滚动');

      final pop = tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await pop;
    });

    testWidgets('竖读模式点「下载当页图片」只给提示，不落盘', (tester) async {
      final saver = MemoryReaderImageSaver();
      await _pumpReader(tester, mode: ReaderMode.vertical, imageSaver: saver);

      await openMore(tester);
      expect(find.textContaining('仅左右翻页模式可用'), findsOneWidget);
      await tester.tap(find.text('下载当页图片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('「下载当页图片」只在左右翻页模式可用'), findsOneWidget);
      expect(saver.files, isEmpty);

      // 等提示自己的计时器跑完，再退出阅读器（避免残留 Overlay / Timer）。
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(tester.binding.handlePopRoute());
      await tester.pump();
      await tester.pumpAndSettle();
      // 把残留的 HUD 定时器也跑完。
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });

    testWidgets('横读模式下载当页：命名 JMComic-[编号]-第几章-第几页', (tester) async {
      final saver = MemoryReaderImageSaver();
      await _pumpReader(tester, pageBytes: syntheticPng(), imageSaver: saver);
      await _tapNext(tester); // -> 第 2 页
      await openMore(tester);
      await tester.tap(find.text('下载当页图片'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(saver.files.keys, <String>['JMComic-7000-第1章-第2页.png']);
      expect(find.textContaining('已保存'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 300));
      unawaited(tester.binding.handlePopRoute());
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
    });
  });
}
