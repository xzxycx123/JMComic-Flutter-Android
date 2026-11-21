import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/jm_comment.dart';
import 'package:jm_comic/features/album/album_providers.dart';
import 'package:jm_comic/features/album/comment_filter.dart';

JmComment _comment(
  String id,
  String content, {
  List<JmComment> replies = const <JmComment>[],
}) =>
    JmComment(id: id, content: content, replies: replies);

void main() {
  group('countEmoji', () {
    test('普通文字 / 中文 / 数字不算 emoji', () {
      expect(countEmoji(''), 0);
      expect(countEmoji('好看，强烈推荐这部作品'), 0);
      expect(countEmoji('JM350234 已阅 2026-11'), 0);
      expect(countEmoji('™'), 0);
    });

    test('常见 Unicode emoji 逐个计数', () {
      expect(countEmoji('好看😀'), 1);
      expect(countEmoji('😀😀'), 2);
      expect(countEmoji('😀😀😀'), 3);
      expect(countEmoji('😀👍🎉'), 3);
      expect(countEmoji('装饰符号★'), 1);
    });

    test('variation selector 不重复计数', () {
      expect(countEmoji('❤️'), 1);
      expect(countEmoji('❤'), 1);
      expect(countEmoji('❤️❤️'), 2);
      expect(countEmoji('™️'), 1);
      expect(countEmoji('1️⃣'), 1);
    });

    test('肤色修饰算同一个 emoji', () {
      expect(countEmoji('👍🏽'), 1);
      expect(countEmoji('👍🏽👍🏻'), 2);
      expect(countEmoji('🙋🏽‍♂️'), 1);
    });

    test('一个 ZWJ 序列只算 1 个', () {
      expect(countEmoji('👨‍👩‍👧'), 1);
      expect(countEmoji('👨‍👩‍👧👨‍👩‍👧'), 2);
      expect(countEmoji('👩‍💻'), 1);
    });

    test('区域指示符成对算 1 面旗', () {
      expect(countEmoji('🇨🇳'), 1);
      expect(countEmoji('🇨🇳🇯🇵'), 2);
    });

    test('混合文本按 emoji 个数计', () {
      expect(countEmoji('好看😀 真的❤️ 快看👨‍👩‍👧'), 3);
    });
  });

  group('looksLikeAdComment / CommentFilter', () {
    const filter = CommentFilter();

    test('边界：2 个 emoji 不算广告，3 个才算', () {
      expect(looksLikeAdComment('两个😀😀'), isFalse);
      expect(looksLikeAdComment('三个😀😀😀'), isTrue);
      expect(looksLikeAdComment('零个'), isFalse);
    });

    test('顶层评论过滤，保留原始顺序', () {
      final items = <JmComment>[
        _comment('1', '普通评论'),
        _comment('2', '两个表情😀😀'),
        _comment('3', '广告评论🎉🎉🎉'),
      ];
      final visible = filter.apply(items);
      expect(visible.map((item) => item.id), <String>['1', '2']);
      // 原始列表没被修改。
      expect(items, hasLength(3));
      expect(filter.hiddenCount(items), 1);
    });

    test('replies 同样过滤，父评论不受影响', () {
      final parent = _comment(
        '10',
        '普通评论',
        replies: <JmComment>[
          _comment('10-1', '回复广告😀😀😀'),
          _comment('10-2', '普通回复'),
          _comment('10-3', '回复两个😀😀'),
        ],
      );
      final items = <JmComment>[parent];

      final visibleReplies = filter.repliesOf(parent);
      expect(
        visibleReplies.map((reply) => reply.id),
        <String>['10-2', '10-3'],
      );
      expect(parent.replies, hasLength(3));
      // 顶层父评论仍在可见列表里。
      expect(filter.apply(items), hasLength(1));
      expect(filter.hiddenCount(items), 1);
    });

    test('hiddenCount 同时统计顶层与 replies（不受 showHidden 影响）', () {
      final items = <JmComment>[
        _comment(
          '1',
          '普通评论',
          replies: <JmComment>[_comment('1-1', '回复广告🎉🎉🎉')],
        ),
        _comment('2', '广告🎉🎉🎉'),
        _comment('3', '两个😀😀'),
      ];
      expect(const CommentFilter().hiddenCount(items), 2);
      const all = CommentFilter(showHidden: true);
      expect(all.hiddenCount(items), 2);
    });

    test('showHidden 时全量展示，replies 全量展示', () {
      const all = CommentFilter(showHidden: true);
      final items = <JmComment>[
        _comment('1', '广告🎉🎉🎉'),
        _comment(
          '2',
          '普通评论',
          replies: <JmComment>[_comment('2-1', '回复广告😀😀😀')],
        ),
      ];
      expect(all.apply(items).map((item) => item.id), <String>['1', '2']);
      expect(all.repliesOf(items[1]).map((item) => item.id), <String>['2-1']);
    });

    test('过滤不改变服务端 total 与条目 id', () {
      final items = <JmComment>[
        _comment('1', '广告🎉🎉🎉'),
        _comment('2', '普通评论'),
      ];
      final state = AlbumCommentsState(items: items, total: 12, page: 1);
      final visible = filter.apply(state.items);
      expect(visible.map((item) => item.id), <String>['2']);
      expect(state.total, 12);
      expect(state.items, hasLength(2));
      // preview 仍按原列表取前 5 条，不会被过滤逻辑改写。
      expect(state.preview, hasLength(2));
    });
  });
}
