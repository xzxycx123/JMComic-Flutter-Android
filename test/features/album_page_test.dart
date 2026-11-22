import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/models/jm_album_detail.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/models/jm_comment.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/features/album/album_page.dart';
import 'package:jm_comic/features/album/album_providers.dart';
import 'package:jm_comic/features/album/widgets/comment_section.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

/// 评论数据由测试逐条指定（`AlbumCommentsNotifier` 的 family 构造器不能带参）。
AlbumCommentsState _commentsState = const AlbumCommentsState();

/// 作者搜索跳转时 `/search` 收到的 uri。
Uri? _searchUri;

class _StubComments extends AlbumCommentsNotifier {
  @override
  Future<AlbumCommentsState> build(String albumId) async => _commentsState;
}

JmAlbumDetail _album({
  String author = '作者甲',
  List<String> tags = const <String>['详情标签'],
}) =>
    JmAlbumDetail(
      id: '100',
      title: '测试本子',
      chapters: const <JmChapterRef>[
        JmChapterRef(id: '101', sort: 1, title: '第一话'),
      ],
      author: author,
      tags: tags,
    );

List<Override> _overrides(JmAlbumDetail album, {ReaderProgress? progress}) =>
    <Override>[
      jmApiProvider.overrideWithValue(FakeJmApi()),
      jmBootstrapProvider.overrideWith((ref) => Completer<JmApi>().future),
      albumDetailProvider(album.id).overrideWith((ref) async => album),
      albumCommentsProvider.overrideWith(_StubComments.new),
      if (progress != null)
        chapterProgressProvider(
          (albumId: album.id, chapterId: album.primaryChapter.id),
        ).overrideWithValue(progress),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initTestStores);
  setUp(() async {
    await clearTestBoxes();
    _commentsState = const AlbumCommentsState();
    _searchUri = null;
  });

  Future<void> pumpAlbum(
    WidgetTester tester, {
    required JmAlbumDetail album,
    ReaderProgress? progress,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(420, 900);
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/album/${album.id}',
      routes: <RouteBase>[
        GoRoute(
          path: '/album/:id',
          builder: (context, state) =>
              AlbumPage(albumId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/search',
          builder: (context, state) {
            _searchUri = state.uri;
            return Scaffold(body: Text('搜索目标页 ${state.uri.query}'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(album, progress: progress),
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('data 状态顶部显示 JM{id}，且不遮挡返回/收藏/分享', (tester) async {
    await pumpAlbum(tester, album: _album());

    final idBadge = find.text('JM100');
    expect(idBadge, findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.byTooltip('分享'), findsOneWidget);

    final back = tester.getTopRight(find.byTooltip('返回'));
    final badgeLeft = tester.getTopLeft(idBadge);
    final badgeRight = tester.getTopRight(idBadge);
    final favorite = tester.getTopLeft(find.byTooltip('收藏'));
    expect(badgeLeft.dx, greaterThanOrEqualTo(back.dx));
    expect(badgeRight.dx, lessThanOrEqualTo(favorite.dx));
    // 同一行工具栏内（没有掉到封面正文里）。
    expect(tester.getCenter(idBadge).dy, lessThan(60));
  });

  testWidgets('详情标签是紧凑药丸：总高 28–32dp、单行省略', (tester) async {
    await pumpAlbum(
      tester,
      album:
          _album(tags: const <String>['详情标签', '一个特别特别特别特别特别特别长的标签名称用来验证省略策略']),
    );

    final shortChip = find.ancestor(
      of: find.text('详情标签'),
      matching: find.byType(AppChip),
    );
    expect(shortChip, findsOneWidget);
    final size = tester.getSize(shortChip);
    expect(size.height, inInclusiveRange(28, 32));
    // 水平 padding 12 + 单行省略，标签不会被撑破。
    expect(size.width, greaterThan(24));

    final longTag = find.text('一个特别特别特别特别特别特别长的标签名称用来验证省略策略');
    expect(longTag, findsOneWidget);
    final longBox = tester.renderObject<RenderBox>(longTag);
    expect(longBox.size.width, lessThanOrEqualTo(200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('封面作者显示「作者：名字」+ 箭头，点击按关键词搜索', (tester) async {
    await pumpAlbum(tester, album: _album(author: '作者甲'));

    // 展示文案是「作者：作者甲」，中括号只出现在需求描述里。
    expect(find.text('作者：作者甲'), findsOneWidget);
    expect(find.text('作者甲'), findsNothing);

    await tester.tap(find.text('作者：作者甲'));
    await tester.pumpAndSettle();

    expect(_searchUri, isNotNull);
    expect(_searchUri!.path, '/search');
    expect(_searchUri!.queryParameters['q'], '作者甲');
    expect(_searchUri!.queryParameters['mode'], 'keyword');
    expect(find.byType(AlbumPage), findsNothing);
  });

  testWidgets('未知作者 / N/A 不触发搜索跳转', (tester) async {
    await pumpAlbum(tester, album: _album(author: 'N/A'));
    expect(find.text('作者：未知作者'), findsOneWidget);

    await tester.tap(find.text('作者：未知作者'));
    await tester.pumpAndSettle();

    expect(_searchUri, isNull);
    expect(find.byType(AlbumPage), findsOneWidget);
  });

  testWidgets('作者名带中括号时显示与搜索都不带括号', (tester) async {
    await pumpAlbum(tester, album: _album(author: '[作者甲]'));

    expect(find.text('作者：作者甲'), findsOneWidget);
    expect(find.text('作者：[作者甲]'), findsNothing);

    await tester.tap(find.text('作者：作者甲'));
    await tester.pumpAndSettle();

    expect(_searchUri!.queryParameters['q'], '作者甲');
    expect(_searchUri!.queryParameters['mode'], 'keyword');
  });

  testWidgets('作者名只有一对空括号时不触发搜索跳转', (tester) async {
    await pumpAlbum(tester, album: _album(author: '[]'));

    expect(find.text('作者：未知作者'), findsOneWidget);

    await tester.tap(find.text('作者：未知作者'));
    await tester.pumpAndSettle();

    expect(_searchUri, isNull);
  });

  testWidgets('第 1 页进度也显示「继续阅读 · 第 1 页」', (tester) async {
    await pumpAlbum(
      tester,
      album: _album(),
      progress: const ReaderProgress(page: 1, total: 12, updatedAt: 0),
    );
    expect(find.text('继续阅读 · 第 1 页'), findsOneWidget);
    expect(find.text('开始阅读'), findsNothing);
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    required bool bottomReached,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider.overrideWith((ref) => Completer<JmApi>().future),
          albumCommentsProvider.overrideWith(_StubComments.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommentSection(
                albumId: '350234',
                totalHint: 3,
                bottomReached: bottomReached,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  List<JmComment> adComments() => const <JmComment>[
        JmComment(id: '1', content: '第一条正常评论'),
        JmComment(id: '2', content: '两个表情😀😀'),
        JmComment(id: '3', content: '第三条正常评论'),
        JmComment(id: '4', content: '第四条正常评论'),
        JmComment(id: '5', content: '广告轰炸😀😀😀'),
        JmComment(id: '6', content: '第六条正常评论'),
      ];

  testWidgets('过滤：≥3 个 emoji 默认隐藏，2 个仍展示，total 不变', (tester) async {
    _commentsState = AlbumCommentsState(items: adComments(), total: 9);
    await pumpSection(tester, bottomReached: false);

    expect(find.text('评论 9'), findsOneWidget);
    expect(find.text('两个表情😀😀'), findsOneWidget);
    expect(find.text('广告轰炸😀😀😀'), findsNothing);
  });

  testWidgets('未展开 / 未触底时不出「显示可能存在广告的评论」', (tester) async {
    _commentsState = AlbumCommentsState(items: adComments(), total: 9);
    await pumpSection(tester, bottomReached: false);
    expect(find.text('显示可能存在广告的评论'), findsNothing);

    // 展开后仍未触底：按钮也不出现。
    await tester.tap(find.text('查看全部 9 条评论'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('第六条正常评论'), findsOneWidget);
    expect(find.text('广告轰炸😀😀😀'), findsNothing);
    expect(find.text('显示可能存在广告的评论'), findsNothing);
  });

  testWidgets('已展开 + 已触底才出现按钮，点击可显示并再次隐藏', (tester) async {
    _commentsState = AlbumCommentsState(items: adComments(), total: 9);
    await pumpSection(tester, bottomReached: true);

    // 未展开时依然不出现。
    expect(find.text('显示可能存在广告的评论'), findsNothing);
    await tester.tap(find.text('查看全部 9 条评论'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    final showButton = find.text('显示可能存在广告的评论');
    expect(showButton, findsOneWidget);
    expect(find.text('广告轰炸😀😀😀'), findsNothing);

    await tester.tap(showButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('广告轰炸😀😀😀'), findsOneWidget);
    expect(find.text('隐藏可能存在广告的评论'), findsOneWidget);

    await tester.tap(find.text('隐藏可能存在广告的评论'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('广告轰炸😀😀😀'), findsNothing);
    expect(find.text('显示可能存在广告的评论'), findsOneWidget);
  });

  testWidgets('replies 里的广告同样默认隐藏', (tester) async {
    _commentsState = const AlbumCommentsState(
      total: 1,
      items: <JmComment>[
        JmComment(
          id: '1',
          content: '父评论正文',
          replies: <JmComment>[
            JmComment(id: '1-1', content: '回复正常内容'),
            JmComment(id: '1-2', content: '回复广告😀😀😀'),
          ],
        ),
      ],
    );
    await pumpSection(tester, bottomReached: false);

    expect(find.text('父评论正文'), findsOneWidget);
    expect(find.text('回复正常内容'), findsOneWidget);
    expect(find.text('回复广告😀😀😀'), findsNothing);
  });

  testWidgets('评论点赞入口已下线：不渲染爱心计数，只留「回复」', (tester) async {
    _commentsState = const AlbumCommentsState(
      total: 2,
      items: <JmComment>[
        JmComment(id: '1', content: '有点赞的评论', likes: 7),
        JmComment(id: '2', content: '零点赞的评论'),
      ],
    );
    await pumpSection(tester, bottomReached: false);

    expect(find.text('有点赞的评论'), findsOneWidget);
    expect(find.text('零点赞的评论'), findsOneWidget);
    expect(find.text('7'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(find.text('回复'), findsWidgets);
  });

  test('解析保留服务端 likes（顶层与 replies）', () {
    final comment = JmComment.fromJson(<String, dynamic>{
      'CID': '1',
      'content': '顶层',
      'likes': '9',
      'replys': <dynamic>[
        <String, dynamic>{'CID': '1-1', 'content': '回复', 'likes': '3'},
      ],
    });
    expect(comment.likes, 9);
    expect(comment.replies.single.likes, 3);
  });
}
