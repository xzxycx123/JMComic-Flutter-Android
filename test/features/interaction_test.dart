import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/models/jm_comment.dart';
import 'package:jm_comic/data/repositories/album_repository.dart';
import 'package:jm_comic/features/album/album_providers.dart';
import 'package:jm_comic/features/album/widgets/comment_section.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

/// 评论区守卫：游客可读、未登录拦在登录门槛、登录后可发。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  Future<void> pumpSection(WidgetTester tester, FakeJmApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          albumRepositoryProvider.overrideWith(
            (ref) async => AlbumRepository(
              api: api,
              progress: ProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress)),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CommentSection(albumId: '350234', totalHint: 3),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('游客可读评论：标题带总数、正文渲染', (tester) async {
    final api = FakeJmApi();
    await pumpSection(tester, api);

    expect(find.text('评论 3'), findsOneWidget);
    expect(find.text('第一条测试评论'), findsOneWidget);
    // 0.3.3：/forum.spoiler 实测恒为 "1"，不再当剧透标记渲染。
    expect(find.text('剧透'), findsNothing);
  });

  testWidgets('未登录点「说点什么…」弹登录门槛，不发请求', (tester) async {
    final api = FakeJmApi();
    await pumpSection(tester, api);

    await tester.tap(find.text('说点什么…'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('登录后才能操作'), findsOneWidget);
    expect(api.postedComments, isEmpty);
  });

  test('评论正文剥离 HTML 标签（站点会吐 <div>/<br>/&nbsp;）', () {
    expect(JmComment.cleanText('<div></div>'), '');
    expect(JmComment.cleanText('好看<div>第二段</div>'), contains('第二段'));
    expect(JmComment.cleanText('好看').contains('<'), isFalse);
    expect(JmComment.cleanText('a<br>b'), 'a\nb');
    expect(JmComment.cleanText('&nbsp;缩进'), '缩进');
    expect(JmComment.cleanText('&lt;3'), '<3');
    expect(JmComment.cleanText('  多行\n\n\n\n段落  '), '多行\n\n段落');

    final parsed = JmComment.fromJson(<String, dynamic>{
      'CID': '1',
      'content': '<div>第一行</div><div>第二行</div>',
      'nickname': '<b>阿B</b>',
      'addtime': '1794625636',
    });
    expect(parsed.content.contains('<'), isFalse);
    expect(parsed.content, contains('第一行'));
    expect(parsed.displayName, '阿B');
  });

  test('已登录时发评论会写到服务端（provider 层）', () async {
    final api = FakeJmApi(loggedIn: true);
    final container = ProviderContainer(
      overrides: <Override>[
        jmApiProvider.overrideWithValue(api),
        jmBootstrapProvider.overrideWith((ref) async => api),
        albumRepositoryProvider.overrideWith(
          (ref) async => AlbumRepository(
            api: api,
            progress: ProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress)),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final first = await container.read(albumCommentsProvider('350234').future);
    expect(first.items, isNotEmpty);

    final message = await container
        .read(albumCommentsProvider('350234').notifier)
        .post('这是一条测试评论');
    expect(message, isNotEmpty);
    expect(api.postedComments, hasLength(1));
    expect(api.postedComments.single.content, '这是一条测试评论');
  });
}
