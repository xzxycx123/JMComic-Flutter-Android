import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/account_session.dart';
import 'package:jm_comic/data/models/download_record.dart';
import 'package:jm_comic/data/models/favorite_item.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/local/favorites_store.dart';
import 'package:jm_comic/data/repositories/album_repository.dart';
import 'package:jm_comic/data/repositories/download_repository.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/features/collect/collect_providers.dart';
import 'package:jm_comic/features/download/download_page.dart'
    show describeRecord;
import 'package:jm_comic/features/download/download_providers.dart';
import 'package:jm_comic/features/download/engine/pdf_sink.dart';
import 'package:jm_comic/features/download/widgets/task_card.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/reader_page.dart';
import 'package:jm_comic/features/reader/reader_providers.dart';
import 'package:jm_comic/features/reader/widgets/page_turn_view.dart';
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

/// 缺专辑 id：结束页必须禁用下载并写明原因。
const ReaderArgs _argsWithoutAlbum = ReaderArgs(
  albumId: '',
  chapterId: '7999',
  title: '第 1 话',
  albumTitle: '',
);

const AccountSession _loggedIn = AccountSession(
  uid: 42,
  username: 'tester',
  state: SessionState.valid,
);

ReaderData _data({
  int pages = 3,
  int initialPage = 1,
  ReaderMode mode = ReaderMode.paged,
  ReaderArgs args = _args,
}) =>
    ReaderData(
      args: args,
      chapter: JmChapter(
        id: args.chapterId,
        title: args.title,
        images: <String>[
          for (var page = 1; page <= pages; page++)
            '${page.toString().padLeft(3, '0')}.webp',
        ],
      ),
      scrambleId: 220980,
      initialPage: initialPage,
      mode: mode,
    );

class _StubReaderController extends ReaderController {
  _StubReaderController(this.data);

  final ReaderData data;

  @override
  Future<ReaderData> build(ReaderArgs arg) async => data;
}

class _StubAccountSession extends AccountSessionNotifier {
  _StubAccountSession(this.value);

  final AccountSession value;

  @override
  Future<AccountSession> build() async => value;
}

/// 点赞接口稳定失败（验证结束页的失败回滚提示）。
class _FailingLikeApi extends FakeJmApi {
  _FailingLikeApi() : super(chapterCount: 1, pagesPerChapter: 3) {
    loggedIn = true;
  }

  @override
  Future<void> likeAlbum(String albumId) async {
    throw const JmContentException('模拟点赞失败');
  }
}

/// 阅读器取页桩：记录每一页的加载请求，可注入「永久缺页」和「挂起」。
class _StubAlbumRepository extends AlbumRepository {
  _StubAlbumRepository(JmApi api, ProgressStore store)
      : super(api: api, progress: store);

  final List<int> loads = <int>[];
  final Set<int> failPages = <int>{};
  Completer<void>? gate;
  int width = 40;
  int height = 60;

  @override
  Future<Uint8List?> loadPage({
    required String photoId,
    required String filename,
    int? scrambleIdOverride,
  }) async {
    final page =
        int.tryParse(RegExp(r'\d+').firstMatch(filename)?.group(0) ?? '') ?? 0;
    loads.add(page);
    final pending = gate;
    if (pending != null) await pending.future;
    if (failPages.contains(page)) return null;
    return syntheticPng(width: width, height: height, seed: page);
  }
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

/// 内存收藏账本：收藏的写操作在 fake-async 区域里不能等 Hive 写盘。
class _MemoryFavoritesStore extends FavoritesStore {
  _MemoryFavoritesStore({
    required super.favorites,
    required super.folders,
    required super.outbox,
  });

  final Map<String, FavoriteItem> _items = <String, FavoriteItem>{};

  @override
  List<FavoriteItem> get items {
    final result = _items.values.toList(growable: true)
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List<FavoriteItem>.unmodifiable(result);
  }

  @override
  int get count => _items.length;

  @override
  bool contains(String albumId) => _items.containsKey(albumId);

  @override
  FavoriteItem? item(String albumId) => _items[albumId];

  @override
  Future<void> put(FavoriteItem item) async => _items[item.albumId] = item;

  @override
  Future<void> remove(String albumId) async => _items.remove(albumId);

  @override
  Future<FavoriteItem> addFromSummary(
    JmAlbumSummary album, {
    String folderId = 'default',
    FavoriteSyncState sync = FavoriteSyncState.localOnly,
  }) async {
    final existing = _items[album.id] ??
        FavoriteItem(
          albumId: album.id,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        );
    final next = existing.copyWith(
      title: album.title,
      author: album.author,
      categoryId: album.categoryId,
      categoryTitle: album.categoryTitle,
      updateAt: album.updateAt,
      sync: sync,
      folderIds: <String>{folderId, 'default', ...existing.folderIds}.toList(),
    );
    _items[album.id] = next;
    return next;
  }
}

class _Harness {
  _Harness({
    required this.container,
    required this.store,
    required this.stub,
    required this.api,
    required this.downloadHistory,
    required this.sink,
    required this.workRoot,
  });

  final ProviderContainer container;
  final ProgressStore store;
  final _StubAlbumRepository stub;
  final FakeJmApi api;
  final MemoryDownloadHistory downloadHistory;
  final MemoryPdfSink sink;
  final Directory workRoot;

  Future<void> flush() =>
      container.read(readerProgressRecorderProvider).flush();

  ReaderProgress? get progress => store.read('7000', '7999');

  DownloadRecord? get latestDownload =>
      downloadHistory.records.isEmpty ? null : downloadHistory.records.first;
}

Future<_Harness> _pumpReader(
  WidgetTester tester, {
  int pages = 3,
  int initialPage = 1,
  ReaderMode mode = ReaderMode.paged,
  Set<int> failPages = const <int>{},
  AccountSession? session,
  Completer<void>? gate,
  ReaderArgs args = _args,
  FakeJmApi? apiOverride,
  int pageWidth = 40,
  int pageHeight = 60,
}) async {
  final api = apiOverride ??
      (FakeJmApi(chapterCount: 1, pagesPerChapter: pages)..loggedIn = true);
  final store =
      _MemoryProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress));
  final stub = _StubAlbumRepository(api, store)
    ..failPages.addAll(failPages)
    ..gate = gate
    ..width = pageWidth
    ..height = pageHeight;
  final downloadHistory = MemoryDownloadHistory();
  final sink = MemoryPdfSink();
  // 必须在 fake-async 区域里用同步 IO：异步创建临时目录会一直等不到回调。
  final workRoot = Directory.systemTemp.createTempSync('jm_end_page_test_');
  final downloadRepository = DownloadRepository(
    apiLoader: () async => api,
    history: downloadHistory,
    sink: sink,
    workRoot: workRoot,
  );
  final container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(await testPreferences()),
      settingsStoreProvider.overrideWithValue(
        _MemorySettingsStore(Hive.box<dynamic>(HiveBoxes.settings)),
      ),
      jmApiProvider.overrideWithValue(api),
      progressStoreProvider.overrideWithValue(store),
      favoritesStoreProvider.overrideWithValue(
        _MemoryFavoritesStore(
          favorites: Hive.box<dynamic>(HiveBoxes.favorites),
          folders: Hive.box<dynamic>(HiveBoxes.favoriteFolders),
          outbox: Hive.box<dynamic>(HiveBoxes.favoriteOutbox),
        ),
      ),
      albumRepositoryProvider.overrideWith((ref) async => stub),
      downloadHistoryProvider.overrideWithValue(downloadHistory),
      downloadRepositoryProvider.overrideWithValue(downloadRepository),
      accountSessionProvider
          .overrideWith(() => _StubAccountSession(session ?? _loggedIn)),
      readerDataProvider.overrideWith(
        () => _StubReaderController(
          _data(pages: pages, initialPage: initialPage, mode: mode, args: args),
        ),
      ),
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
        builder: (context, state) => ReaderPage(args: args),
      ),
      GoRoute(
        path: '/download',
        builder: (context, state) => const Scaffold(body: Text('下载页')),
      ),
    ],
  );
  addTearDown(() {
    router.dispose();
    container.dispose();
    // 不能在这里 await 真实延迟：addTearDown 仍跑在测试的 fake-async 区域里。
    try {
      if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
    } catch (_) {
      // 任务收尾还在用临时文件时忽略（系统临时目录会自行清理）。
    }
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.tap(find.text('打开阅读器'));
  await tester.pumpAndSettle();
  return _Harness(
    container: container,
    store: store,
    stub: stub,
    api: api,
    downloadHistory: downloadHistory,
    sink: sink,
    workRoot: workRoot,
  );
}

/// 点右侧 1/3 翻到下一页。
///
/// 第一帧派发点击并让翻页动画开始计时，第二帧把 240ms 动画走完
/// （只 pump 一次带时长的帧时，ticker 会把那一帧当作起始时刻，动画不会前进）。
Future<void> _tapNext(WidgetTester tester) async {
  final rect = tester.getRect(find.byType(ReaderTapZones));
  await tester.tapAt(Offset(rect.left + rect.width * 0.9, rect.center.dy));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  int steps = 40,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var index = 0; index < steps; index++) {
    if (predicate()) return;
    await tester.pump(step);
  }
}

/// 等下载任务进入终态。
///
/// worker 会把页面落成临时 PNG（真实文件 IO）：fake-async 里 IO 完成回调不会自己跑，
/// 每个周期用 runAsync 让真实事件循环推进一次，再 pump 一次刷新 fake-zone 的后续任务。
Future<void> _waitDownload(
  WidgetTester tester,
  _Harness harness, {
  required bool Function(DownloadRecord record) done,
  int cycles = 120,
}) async {
  for (var index = 0; index < cycles; index++) {
    final record = harness.latestDownload;
    if (record != null && done(record)) {
      await tester.pump();
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    // 带时长的 pump 才会推进 fake-async 的时钟（单页重试的退避延迟靠它）。
    await tester.pump(const Duration(milliseconds: 50));
  }
  final record = harness.latestDownload;
  expect(
    record != null && done(record),
    isTrue,
    reason: '下载任务没有在预期时间内进入终态，当前：${record?.state}',
  );
}

/// 结束页是否真的在可视区域内（PageView 会预先构建相邻页，不能用 find 直接判断）。
bool _endPageOnScreen(WidgetTester tester) {
  final finder = find.text('（全书完）');
  if (finder.evaluate().isEmpty) return false;
  final rect = tester.getRect(finder);
  final viewport = tester.getRect(find.byType(PageTurnView));
  return rect.left < viewport.right && rect.right > viewport.left;
}

/// 让 `Image.memory` 的解码在 fake-async 里真正完成（竖读要靠图片真实高度撑开列表）。
Future<void> _settleImages(WidgetTester tester) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

/// HUD 会自动隐藏：需要读 HUD 时先确保它真的显示出来。
Future<void> _ensureHud(WidgetTester tester) async {
  for (var attempt = 0; attempt < 4; attempt++) {
    if (find.byType(AppIconButton).evaluate().isNotEmpty) return;
    // 左右翻页用三分区，竖读用整页点击切 HUD。
    final target = find.byType(ReaderTapZones).evaluate().isNotEmpty
        ? find.byType(ReaderTapZones)
        : find.byType(ScrollReaderView);
    await tester.tapAt(tester.getRect(target).center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// 跑完 HUD / Toast 的计时器并退出阅读器，避免测试结束时还有 pending timer。
///
/// 这里刻意不用 pumpAndSettle：任何瞬时的 loading 动画都不该把清理拖死。
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

  testWidgets('读到最后一页后出现（全书完）与下载/收藏/点赞，进度停在第 3 页', (tester) async {
    final harness = await _pumpReader(tester);
    expect(_endPageOnScreen(tester), isFalse, reason: '第 1 页时还没有结束页');

    await _tapNext(tester); // -> 2
    await _tapNext(tester); // -> 3（最后一页）
    expect(_endPageOnScreen(tester), isFalse);

    await _tapNext(tester); // -> 结束页
    expect(_endPageOnScreen(tester), isTrue);
    expect(find.text('（全书完）'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '下载'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '收藏'), findsOneWidget);
    expect(find.widgetWithText(AppButton, '点赞'), findsOneWidget);
    await _ensureHud(tester);
    expect(
      find.textContaining('第 3/3 页'),
      findsOneWidget,
      reason: '结束页不计入页码，HUD 仍显示第 3/3 页',
    );

    // 已经到底：再点右侧不会继续翻页，也不会写出第 4 页。
    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue);

    unawaited(tester.binding.handlePopRoute());
    await tester.pumpAndSettle();
    await harness.flush();
    expect(harness.progress!.page, 3);
    expect(harness.progress!.total, 3);

    await _drain(tester);
  });

  testWidgets('结束页可以滑回最后一页（不影响正常翻页）', (tester) async {
    await _pumpReader(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue);

    await tester.fling(find.byType(PageTurnView), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();

    expect(_endPageOnScreen(tester), isFalse, reason: '右滑回到最后一页');
    await _ensureHud(tester);
    expect(find.textContaining('第 3/3 页'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('下载：点击只弹一条真实结果的 Toast，复用缓存合成 PDF，任务在下载记录里可见', (tester) async {
    final harness = await _pumpReader(tester);
    final loadsBeforeExport = harness.stub.loads.length;
    expect(loadsBeforeExport, greaterThanOrEqualTo(3), reason: '三页都已预取进缓存');

    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue);

    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('已加入下载队列'),
      findsOneWidget,
      reason: '点击后只弹一条与结果一致的提示',
    );
    expect(find.textContaining('已在下载队列中'), findsNothing);

    await _waitDownload(tester, harness, done: (record) => record.isFinished);
    final record = harness.latestDownload!;
    expect(record.state, DownloadState.succeeded);
    expect(record.chapterId, '7999');
    expect(record.chapterTitle, '第 1 话');
    expect(record.pageCount, 3);
    expect(record.pdfName, 'JM7000 - 测试本.pdf');
    expect(harness.stub.loads.length, loadsBeforeExport, reason: '三页全部来自阅读缓存');
    expect(harness.sink.files, hasLength(1));
    expect(
      latin1.decode(harness.sink.files.values.single, allowInvalid: true),
      contains('/Count 3'),
    );
    expect(harness.workRoot.listSync(), isEmpty, reason: '临时页目录要清空');

    // 既有下载页的数据源（记录流 + 文案）能看到这个任务。
    final records = harness.container.read(downloadRecordsProvider);
    expect(records.map((item) => item.workId), contains(record.workId));
    expect(describeRecord(record), '3 页 · JM7000 - 测试本.pdf');

    await _drain(tester);
  });

  testWidgets('下载：缺页时通过既有加载管线补齐，PDF 页序与总页数正确', (tester) async {
    // 从第 8 页进入：预取窗口是 6..8，1..5 还没加载，正好验证「缺页补齐」。
    final harness = await _pumpReader(tester, pages: 8, initialPage: 8);
    await tester.pumpAndSettle();
    harness.stub.loads.clear();

    await _tapNext(tester); // 最后一页 -> 结束页
    expect(_endPageOnScreen(tester), isTrue);

    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    await _waitDownload(tester, harness, done: (record) => record.isFinished);

    final record = harness.latestDownload!;
    expect(record.state, DownloadState.succeeded);
    expect(record.pageCount, 8);
    expect(
      harness.stub.loads,
      <int>[1, 2, 3, 4, 5],
      reason: '只补齐没缓存的页，并且按页序请求',
    );
    expect(
      latin1.decode(harness.sink.files.values.single, allowInvalid: true),
      contains('/Count 8'),
    );

    await _drain(tester);
  });

  testWidgets('下载：永远补不齐的页导致任务失败，不产出缺页 PDF', (tester) async {
    final harness = await _pumpReader(
      tester,
      pages: 8,
      initialPage: 8,
      failPages: <int>{1},
    );
    await tester.pumpAndSettle();

    await _tapNext(tester);
    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    await _waitDownload(tester, harness, done: (record) => record.isFinished);

    final record = harness.latestDownload!;
    expect(record.state, DownloadState.failed);
    expect(record.error, contains('第 1 页'));
    expect(harness.sink.files, isEmpty, reason: '缺页不能静默成功');

    await _drain(tester);
  });

  testWidgets('重复点击：任务进行中再点不会重复入队', (tester) async {
    final harness = await _pumpReader(tester, pages: 8, initialPage: 8);
    await tester.pumpAndSettle();
    // 打开阅读器之后再挂起取页：避免首屏预取一直转圈导致 pumpAndSettle 卡住。
    final gate = Completer<void>();
    harness.stub.gate = gate;

    await _tapNext(tester);
    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.downloadHistory.records, hasLength(1));

    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      harness.downloadHistory.records,
      hasLength(1),
      reason: '进行中重复点击不产生第二条任务',
    );

    gate.complete();
    await _waitDownload(tester, harness, done: (record) => record.isFinished);
    expect(harness.latestDownload!.state, DownloadState.succeeded);
    await _drain(tester);
  });

  testWidgets('收藏：复用收藏账本，选中态与提示可撤销', (tester) async {
    // 本地收藏（未登录）走的就是「本地账本」这条既有路径。
    final harness = await _pumpReader(tester, session: AccountSession.local);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '收藏'));
    await tester.pump();
    await tester.pump();
    expect(
      harness.container.read(favoriteIdsProvider),
      contains('7000'),
    );
    expect(find.widgetWithText(AppButton, '已收藏'), findsOneWidget);
    expect(find.textContaining('已收藏'), findsWidgets);

    // 等 Toast 自己消失，避免命中它的文字。
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.widgetWithText(AppButton, '已收藏'));
    await tester.pump();
    await tester.pump();
    expect(
      harness.container.read(favoriteIdsProvider),
      isNot(contains('7000')),
    );
    expect(find.widgetWithText(AppButton, '收藏'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('点赞：复用 albumLikeProvider，已登录时发送并变「已点赞」', (tester) async {
    final harness = await _pumpReader(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '点赞'));
    await tester.pump();
    await _pumpUntil(tester, () => harness.api.likedAlbums.contains('7000'));
    await tester.pump();

    expect(harness.api.likedAlbums, contains('7000'));
    expect(find.widgetWithText(AppButton, '已点赞 1'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('点赞：未登录时先弹登录门槛，不直接发请求', (tester) async {
    final harness = await _pumpReader(tester, session: AccountSession.local);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '点赞'));
    await tester.pumpAndSettle();

    expect(find.text('登录后才能操作'), findsOneWidget);
    expect(harness.api.likedAlbums, isEmpty);
    await tester.tap(find.text('先不登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录后才能操作'), findsNothing);

    await _drain(tester);
  });

  testWidgets('上下滚动模式：滑到底部也能看到结束页', (tester) async {
    await _pumpReader(
      tester,
      mode: ReaderMode.vertical,
      pageWidth: 80,
      pageHeight: 600,
    );
    await _settleImages(tester);

    await tester.fling(
      find.byType(ScrollReaderView),
      const Offset(0, -2000),
      1200,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('（全书完）'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('上下滚动模式：页码比率扣掉结束页，滚到底停在 N/N，回滚可离开结束页', (tester) async {
    await _pumpReader(
      tester,
      mode: ReaderMode.vertical,
      pageWidth: 80,
      pageHeight: 600,
    );
    await _settleImages(tester);

    final view = tester.widget<ScrollReaderView>(find.byType(ScrollReaderView));
    final position = view.controller.position;
    final screenHeight = tester.getSize(find.byType(ScrollReaderView)).height;
    expect(
      view.footerExtent,
      closeTo(screenHeight * 0.72, 0.5),
      reason: '结束页高度就是阅读器扣掉的 footerExtent',
    );

    // HUD 拖到最后一页：只按正文高度定位，结束页不参与页比率。
    await _ensureHud(tester);
    final track = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(track.right - 1, track.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent - view.footerExtent, 2),
      reason: '第 N 页的定位不应把结束页算进去',
    );

    // 继续滚到底：结束页出现，页码停在 N/N。
    await tester.fling(
      find.byType(ScrollReaderView),
      const Offset(0, -2000),
      1200,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('（全书完）'), findsOneWidget);
    await _ensureHud(tester);
    expect(find.textContaining('第 3/3 页'), findsOneWidget);
    expect(find.textContaining('100%'), findsOneWidget);

    // 回滚：结束页离开视口，页码回落而不是卡在 N/N。
    await tester.fling(
      find.byType(ScrollReaderView),
      const Offset(0, 1600),
      1500,
    );
    await tester.pumpAndSettle();
    expect(
      find.text('（全书完）'),
      findsNothing,
      reason: '内层滚动视图不能抢外层回滚手势',
    );
    await _ensureHud(tester);
    expect(find.textContaining('第 3/3 页'), findsNothing);

    await _drain(tester);
  });

  testWidgets('上下滚动模式：结束页上的下载按钮可用', (tester) async {
    final harness = await _pumpReader(
      tester,
      mode: ReaderMode.vertical,
      pageWidth: 80,
      pageHeight: 600,
    );
    await _settleImages(tester);

    await tester.fling(
      find.byType(ScrollReaderView),
      const Offset(0, -2000),
      1200,
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 300));

    final download = find.widgetWithText(AppButton, '下载');
    await tester.ensureVisible(download);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(download);
    // 竖读外层有双击缩放识别器，单击会等双击判定，多 pump 一点。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(harness.downloadHistory.records, hasLength(1));
    await _waitDownload(tester, harness, done: (record) => record.isFinished);
    expect(harness.latestDownload!.state, DownloadState.succeeded);
    expect(harness.latestDownload!.pageCount, 3);

    await _drain(tester);
  });

  testWidgets('结束页返回上一页后仍可再次进入结束页', (tester) async {
    await _pumpReader(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue);

    await tester.fling(find.byType(PageTurnView), const Offset(500, 0), 1200);
    await tester.pumpAndSettle();
    expect(_endPageOnScreen(tester), isFalse);

    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue, reason: '返回上一页后翻页仍然可用');

    await _drain(tester);
  });

  testWidgets('缺少专辑信息时下载置灰，并写明原因', (tester) async {
    final harness = await _pumpReader(tester, args: _argsWithoutAlbum);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    expect(_endPageOnScreen(tester), isTrue);

    final download = tester.widget<AppButton>(
      find.widgetWithText(AppButton, '下载'),
    );
    expect(
      download.onPressed,
      isNull,
      reason: 'canDownloadReaderUnit=false 必须禁用',
    );
    expect(find.textContaining('缺少可导出的页面信息'), findsOneWidget);

    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    expect(harness.downloadHistory.records, isEmpty);

    await _drain(tester);
  });

  testWidgets('下载页任务卡能看到失败任务与缺页原因', (tester) async {
    const record = DownloadRecord(
      workId: 'w1',
      albumId: '7000',
      chapterId: '7999',
      chapterTitle: '第 1 话',
      title: '测试本',
      state: DownloadState.failed,
      status: '下载失败',
      detail: '第 1 页没有取到，未生成 PDF',
      error: '第 1 页没有取到，未生成 PDF',
      total: 8,
      done: 3,
      percent: 37,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider
              .overrideWith((ref) => Completer<FakeJmApi>().future),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: TaskCard(record: record),
            ),
          ),
        ),
      ),
    );

    expect(find.text('测试本'), findsOneWidget);
    expect(find.textContaining('下载失败'), findsOneWidget);
    expect(find.textContaining('第 1 页没有取到'), findsOneWidget);
  });

  testWidgets('收藏：provider 重建后状态仍在（真实账本）', (tester) async {
    final harness = await _pumpReader(tester, session: AccountSession.local);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '收藏'));
    await tester.pump();
    await tester.pump();
    expect(harness.container.read(favoriteIdsProvider), contains('7000'));

    harness.container.invalidate(favoritesItemsProvider);
    await tester.pump();
    await tester.pump();
    expect(
      harness.container.read(favoriteIdsProvider),
      contains('7000'),
      reason: '收藏状态来自本地账本，provider 重建后不能丢',
    );
    expect(find.widgetWithText(AppButton, '已收藏'), findsOneWidget);

    await _drain(tester);
  });

  testWidgets('点赞：已点赞时再点只提示，不重复发请求', (tester) async {
    final harness = await _pumpReader(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '点赞'));
    await tester.pump();
    await _pumpUntil(tester, () => harness.api.likedAlbums.contains('7000'));
    await tester.pump();
    expect(harness.api.likedAlbums, hasLength(1));

    // 等 Toast 消失，再点「已点赞」。
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.widgetWithText(AppButton, '已点赞 1'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('已经点过赞了'), findsOneWidget);
    expect(harness.api.likedAlbums, hasLength(1), reason: '不重复发请求');

    await _drain(tester);
  });

  testWidgets('点赞失败：回滚到未赞并提示原因', (tester) async {
    final harness = await _pumpReader(tester, apiOverride: _FailingLikeApi());
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(AppButton, '点赞'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.widgetWithText(AppButton, '点赞'),
      findsOneWidget,
      reason: '失败后回滚为未赞',
    );
    expect(find.textContaining('点赞失败'), findsOneWidget);
    expect(harness.api.likedAlbums, isEmpty);

    await _drain(tester);
  });

  testWidgets('已有进行中的任务：只提示「已在下载队列中」，不先报成功', (tester) async {
    final harness = await _pumpReader(tester);
    await harness.downloadHistory.add(
      const DownloadRecord(
        workId: 'w-active',
        albumId: '7000',
        state: DownloadState.running,
        status: '下载中',
        createdAt: 1,
        updatedAt: 1,
      ),
    );

    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);
    await tester.tap(find.widgetWithText(AppButton, '下载'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('已在下载队列中'), findsOneWidget);
    expect(
      find.textContaining('已加入下载队列'),
      findsNothing,
      reason: '复用时不能先弹成功提示再被顶掉',
    );
    expect(harness.downloadHistory.records, hasLength(1));

    await _drain(tester);
  });
}
