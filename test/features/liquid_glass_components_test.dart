import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/jm_album_detail.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/models/jm_search_page.dart';
import 'package:jm_comic/data/repositories/search_repository.dart';
import 'package:jm_comic/features/album/album_page.dart';
import 'package:jm_comic/features/album/album_providers.dart';
import 'package:jm_comic/features/album/widgets/comment_section.dart';
import 'package:jm_comic/features/search/search_page.dart';
import 'package:jm_comic/features/search/search_providers.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

const _album = JmAlbumDetail(
  id: '100',
  title: '测试本子',
  tags: ['详情标签'],
  chapters: [JmChapterRef(id: '101', sort: 1, title: '第一话')],
);

Widget _liquidGlass(Widget app) => LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: app,
    );

Widget _scope(BuildContext context, Widget? child) => InterfaceStyleScope(
      style: AppInterfaceStyle.liquidGlass,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
          disableAnimations: true,
        ),
        child: child!,
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestStores);
  setUp(clearTestBoxes);

  for (final page in [1, 12]) {
    testWidgets('详情主按钮进入阅读器第 $page 页', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 640);
      addTearDown(tester.view.reset);
      Uri? readerUri;
      final router = GoRouter(
        initialLocation: '/album/100',
        routes: [
          GoRoute(
            path: '/album/:id',
            builder: (context, state) =>
                AlbumPage(albumId: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/reader',
            builder: (context, state) {
              readerUri = state.uri;
              return const Scaffold(body: Text('阅读器目标页'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      final api = FakeJmApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jmApiProvider.overrideWithValue(api),
            jmBootstrapProvider
                .overrideWith((ref) => Completer<FakeJmApi>().future),
            albumDetailProvider('100').overrideWith((ref) async => _album),
            albumCommentsProvider.overrideWith(_EmptyComments.new),
            chapterProgressProvider((albumId: '100', chapterId: '101'))
                .overrideWithValue(
              page == 1
                  ? null
                  : ReaderProgress(page: page, total: 22, updatedAt: 0),
            ),
          ],
          child: _liquidGlass(
            MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light(),
              builder: _scope,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = page == 1 ? '开始阅读' : '继续阅读 · 第 $page 页';
      final action = find.ancestor(
        of: find.text(label),
        matching: find.byType(GlassButton),
      );
      expect(action, findsOneWidget);
      expect(tester.getSize(action).height, 48);
      expect(find.text('详情标签'), findsOneWidget);
      final download = find.ancestor(
        of: find.text('下载'),
        matching: find.byType(AppButton),
      );
      expect(tester.getSize(download).width, 108);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('阅读器目标页'), findsOneWidget);
      expect(readerUri?.queryParameters, containsPair('album', '100'));
      expect(readerUri?.queryParameters, containsPair('chapter', '101'));
      expect(readerUri?.queryParameters, containsPair('page', '$page'));
    });
  }

  testWidgets('窄屏键盘弹出时评论面板返回草稿', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    CommentDraft? result;
    await tester.pumpWidget(
      ProviderScope(
        child: _liquidGlass(
          MaterialApp(
            theme: AppTheme.light(),
            builder: _scope,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showCommentComposer(context, albumId: '100');
                  },
                  child: const Text('打开评论表单'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开评论表单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    await tester.pump();
    final send = find.text('发送');
    expect(tester.getBottomRight(send).dy, lessThan(330));
    await tester.enterText(find.byType(EditableText), '  评论草稿  ');
    await tester.tap(find.byType(AppSwitch));
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();
    expect(result?.content, '评论草稿');
    expect(result?.spoiler, isTrue);
  });

  for (final style in AppInterfaceStyle.values) {
    testWidgets('长按历史菜单只删除所选记录（${style.name}）', (tester) async {
      final history = _MemorySearchHistory();
      await history.push('保留关键词');
      await history.push('待删除关键词');
      final container = ProviderContainer(
        overrides: [
          searchHistoryStoreProvider.overrideWithValue(history),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _liquidGlass(
            MaterialApp(
              theme: AppTheme.dark(),
              builder: (context, child) => InterfaceStyleScope(
                style: style,
                child: child!,
              ),
              home: const SearchPage(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entry = find.text('待删除关键词');
      expect(find.text('删除'), findsNothing);
      await tester.longPress(entry);
      await tester.pumpAndSettle();
      final delete = find.text('删除');
      expect(delete, findsOneWidget);
      expect(container.read(searchHistoryProvider), hasLength(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(delete, findsNothing);
      expect(container.read(searchHistoryProvider), hasLength(2));
      await tester.longPress(entry);
      await tester.pumpAndSettle();
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text('待删除关键词'), findsNothing);
      expect(find.text('保留关键词'), findsOneWidget);
      expect(container.read(searchControllerProvider).valueOrNull, isNull);
    });
  }

  testWidgets('数字详情标签直接搜关键词，结果显示作者和标签', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    final api = _TagSearchApi();
    final history = _MemorySearchHistory();
    final router = GoRouter(
      initialLocation: '/album/100',
      routes: [
        GoRoute(
            path: '/album/:id',
            builder: (_, state) =>
                AlbumPage(albumId: state.pathParameters['id']!),),
        GoRoute(
          path: '/search',
          builder: (_, state) => SearchPage(
            initialQuery: state.uri.queryParameters['q'],
            forceKeyword: state.uri.queryParameters['mode'] == 'keyword',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        jmApiProvider.overrideWithValue(api),
        jmBootstrapProvider.overrideWith((_) => Completer<FakeJmApi>().future),
        albumDetailProvider('100').overrideWith((_) async =>
            const JmAlbumDetail(id: '100', title: '详情', tags: ['350234']),),
        albumCommentsProvider.overrideWith(_EmptyComments.new),
        searchHistoryStoreProvider.overrideWithValue(history),
        searchRepositoryProvider.overrideWith(
            (_) async => SearchRepository(api: api, history: history),),
      ],
      child: _liquidGlass(MaterialApp.router(
          routerConfig: router, builder: _scope, theme: AppTheme.light(),),),
    ),);
    await tester.pumpAndSettle();
    await tester.tap(find.text('350234'));
    await tester.pumpAndSettle();
    final searchPage = find.byType(SearchPage);
    expect(searchPage, findsOneWidget);
    expect(GoRouterState.of(tester.element(searchPage)).uri.path, '/search');
    expect(api.lastQuery, '350234');
    expect(find.text('测试作者'), findsOneWidget);
    expect(find.text('服务端标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MemorySearchHistory extends Fake implements SearchHistoryStore {
  final _terms = <String>[];

  @override
  List<String> read() => List.of(_terms);

  @override
  Future<List<String>> push(String keyword, {int limit = 10}) async {
    _terms.remove(keyword);
    _terms.insert(0, keyword);
    return read();
  }

  @override
  Future<void> remove(String keyword) async {
    _terms.remove(keyword);
  }
}

class _TagSearchApi extends FakeJmApi {
  String? lastQuery;

  @override
  Future<JmSearchPage> search(
      {required String query,
      int page = 1,
      AlbumOrder order = AlbumOrder.latestUpdate,}) async {
    lastQuery = query;
    return JmSearchPage(query: query, total: 1, page: page, content: const [
      JmAlbumSummary(id: '123', title: '搜索结果', author: '测试作者', tags: ['服务端标签']),
    ],);
  }
}

class _EmptyComments extends AlbumCommentsNotifier {
  @override
  Future<AlbumCommentsState> build(String albumId) async =>
      const AlbumCommentsState();
}
