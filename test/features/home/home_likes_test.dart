import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/data/models/jm_album_meta.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/home/home_likes.dart';
import 'package:jm_comic/features/home/home_page.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_env.dart';

Future<void> _pumpFrames(WidgetTester tester, {int frames = 10}) async {
  for (var index = 0; index < frames; index++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

ProviderContainer _container(Future<JmAlbumMeta> Function(String) fetcher) {
  final container = ProviderContainer(
    overrides: <Override>[
      albumMetaFetcherProvider.overrideWithValue(fetcher),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  group('withResolvedMeta', () {
    const album = JmAlbumSummary(id: '7', title: 'A');

    test('已确认的正数覆盖卡片数据', () {
      expect(withResolvedMeta(album, likes: 42).likes, 42);
      expect(withResolvedMeta(album, likes: 42).displayLikes, '42');
    });

    test('缺失保持原样（显示 --）', () {
      expect(withResolvedMeta(album).likes, 0);
      expect(withResolvedMeta(album).displayLikes, JmAlbumSummary.noLikeCount);
    });

    test('JmAPI 给的真实 0 不会覆盖详情页已有的正数', () {
      const withDetail = JmAlbumSummary(id: '7', title: 'A', likes: 355);
      expect(withResolvedMeta(withDetail, likes: 0).likes, 355);
      expect(withResolvedMeta(withDetail, likes: 400).likes, 400);
    });

    test('拿到的 tags 并进卡片；空标签不动原数据', () {
      final withTags = withResolvedMeta(
        album,
        tags: const <String>['扶她', '全彩'],
      );
      expect(withTags.tags, <String>['扶她', '全彩']);
      expect(withTags.cardTags.first, '扶她');
      expect(
        withResolvedMeta(withTags, tags: const <String>[]).tags,
        <String>['扶她', '全彩'],
      );
    });
  });

  group('AlbumMetaNotifier（JmAPI 取数）', () {
    test('同一个 id 只请求一次，结果进 state', () async {
      final calls = <String>[];
      final container = _container((String id) async {
        calls.add(id);
        return const JmAlbumMeta(likes: 355, tags: <String>['扶她']);
      });
      final notifier = container.read(albumMetaProvider.notifier);

      notifier.ensure(<String>['1490702']);
      notifier.ensure(<String>['1490702']);
      await pumpEventQueue();
      notifier.ensure(<String>['1490702']);
      await pumpEventQueue();

      expect(calls, <String>['1490702']);
      expect(container.read(albumMetaProvider).likes['1490702'], 355);
      expect(container.read(albumMetaProvider).tagsOf('1490702'), <String>['扶她']);
    });

    test('并发上限：一屏卡片不会瞬间把整页打到服务端', () async {
      final pending = <Completer<JmAlbumMeta>>[];
      final container = _container((String id) {
        final completer = Completer<JmAlbumMeta>();
        pending.add(completer);
        return completer.future;
      });
      final notifier = container.read(albumMetaProvider.notifier);

      notifier.ensure(List<String>.generate(10, (index) => '$index'));
      await pumpEventQueue();
      expect(pending.length, AlbumMetaNotifier.maxConcurrent);

      pending.first.complete(const JmAlbumMeta(likes: 1));
      await pumpEventQueue();
      expect(pending.length, AlbumMetaNotifier.maxConcurrent + 1);

      // 一边完成一边排队：全部 id 都要拿到结果。
      var guard = 0;
      while (container.read(albumMetaProvider).likes.length < 10) {
        for (final completer in pending) {
          if (!completer.isCompleted) {
            completer.complete(const JmAlbumMeta(likes: 1));
          }
        }
        await pumpEventQueue();
        if (++guard > 20) break;
      }
      expect(container.read(albumMetaProvider).likes.length, 10);
    });

    test('失败一次后，下次 ensure 重试成功', () async {
      var calls = 0;
      final container = _container((String id) async {
        calls++;
        if (calls == 1) {
          throw StateError('模拟网络失败');
        }
        return const JmAlbumMeta(likes: 42);
      });
      final notifier = container.read(albumMetaProvider.notifier);

      notifier.ensure(<String>['7']);
      await pumpEventQueue();
      expect(container.read(albumMetaProvider).likes.containsKey('7'), isFalse);

      notifier.ensure(<String>['7']);
      await pumpEventQueue();
      expect(calls, 2);
      expect(container.read(albumMetaProvider).likes['7'], 42);
    });

    test('连续失败达到上限后放弃该 id，不再发请求', () async {
      var calls = 0;
      final container = _container((String id) async {
        calls++;
        throw StateError('模拟网络失败');
      });
      final notifier = container.read(albumMetaProvider.notifier);

      for (var round = 0; round < 4; round++) {
        notifier.ensure(<String>['7']);
        await pumpEventQueue();
      }

      expect(calls, AlbumMetaNotifier.maxAttempts);
      expect(container.read(albumMetaProvider).failed, contains('7'));
    });

    test('真实 0 赞会写入 state（不再靠 -- 猜）', () async {
      final container = _container((String id) async => const JmAlbumMeta());
      final notifier = container.read(albumMetaProvider.notifier);

      notifier.ensure(<String>['7']);
      await pumpEventQueue();

      expect(container.read(albumMetaProvider).isResolved('7'), isTrue);
      expect(container.read(albumMetaProvider).likes['7'], 0);
    });
  });

  testWidgets('首页卡片显示 JmAPI 返回的点赞量', (tester) async {
    final requested = <String>[];
    final api = FakeJmApi()
      ..likesByAlbum.addAll(<String, int>{
        '1485385': 1234,
        '1490702': 42,
        '1490703': 21,
      });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: api),
          ),
          albumMetaFetcherProvider.overrideWithValue((String id) async {
            requested.add(id);
            return JmAlbumMeta(likes: api.likesByAlbum[id] ?? 0);
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    expect(requested, isNotEmpty);
    // 横滑分节里的 1485385（首屏就构建）拿到 JmAPI 的 1234。
    expect(find.text('1234'), findsWidgets);

    // 网格在折叠线以下：滚到网格后，fixture 首条 1490702 显示 42。
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    await _pumpFrames(tester, frames: 4);
    expect(find.text('42'), findsWidgets);
  });

  testWidgets('首页卡片在作者名下方显示作品标签（不是分类名）', (tester) async {
    final api = FakeJmApi()
      ..tagsByAlbum.addAll(<String, List<String>>{
        '1490702': <String>['扶她', '全彩', '中文'],
      });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(api),
          jmBootstrapProvider.overrideWith((ref) async => api),
          homeRepositoryProvider.overrideWith(
            (ref) async => HomeRepository(api: api),
          ),
          albumMetaFetcherProvider.overrideWithValue((String id) async {
            return JmAlbumMeta(
              likes: api.likesByAlbum[id] ?? 0,
              tags: api.tagsByAlbum[id] ?? const <String>[],
            );
          }),
        ],
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await _pumpFrames(tester);

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -600),
    );
    await tester.pump();
    await _pumpFrames(tester, frames: 6);

    expect(find.text('扶她'), findsWidgets);
    expect(find.text('全彩'), findsWidgets);
  });
}
