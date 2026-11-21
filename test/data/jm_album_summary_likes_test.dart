import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';

void main() {
  group('likes 解析', () {
    test('likes 字段直读', () {
      final album = JmAlbumSummary.fromJson(<String, dynamic>{
        'id': '1',
        'name': 'A',
        'likes': 4321,
      });
      expect(album.likes, 4321);
      expect(album.displayLikes, '4321');
    });

    test('like_count / likes_count 兜底', () {
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'like_count': 12})
            .likes,
        12,
      );
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes_count': 34})
            .likes,
        34,
      );
    });

    test('字符串形态的计数（含千分位 / 单位）', () {
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': '1,234'})
            .likes,
        1234,
      );
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': '1.2万'})
            .likes,
        12000,
      );
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': '2.5k'})
            .likes,
        2500,
      );
    });

    test('缺失 / 乱码 / 负数一律 0', () {
      expect(JmAlbumSummary.fromJson(<String, dynamic>{'id': '1'}).likes, 0);
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': null})
            .likes,
        0,
      );
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': 'N/A'})
            .likes,
        0,
      );
      expect(
        JmAlbumSummary.fromJson(<String, dynamic>{'id': '1', 'likes': -5})
            .likes,
        0,
      );
    });

    test('fixture 列表项没有 likes 字段时按 0', () {
      final album = JmAlbumSummary.fromJson(<String, dynamic>{
        'id': '1490663',
        'name': '榜一大哥的女主播收藏計劃 Vol.4',
        'category': <String, dynamic>{'id': '4', 'title': '其他類'},
        'liked': false,
        'is_favorite': false,
        'update_at': 1794624453,
        'adddate': '2026-11-14',
      });
      expect(album.likes, 0);
      expect(album.displayLikes, JmAlbumSummary.noLikeCount);
      expect(album.displayLikes, '--');
    });
  });

  group('toJson / copyWith', () {
    final album = JmAlbumSummary.fromJson(<String, dynamic>{
      'id': '7',
      'name': 'B',
      'likes': 99,
    });

    test('toJson 带 likes 且可回环', () {
      final json = album.toJson();
      expect(json['likes'], 99);
      expect(JmAlbumSummary.fromJson(json).likes, 99);
      expect(JmAlbumSummary.fromJson(json).title, 'B');
    });

    test('copyWith 保留 likes，也可覆盖', () {
      expect(album.copyWith(liked: true).likes, 99);
      expect(album.copyWith(likes: 1).likes, 1);
      expect(album.copyWith(likes: 1).liked, isFalse);
    });
  });

  group('displayLikes 展示', () {
    String render(int likes) =>
        JmAlbumSummary(id: '1', title: 'A', likes: likes).displayLikes;

    test('0 统一显示 --', () {
      expect(render(0), '--');
    });

    test('一万以内原样', () {
      expect(render(1), '1');
      expect(render(9999), '9999');
    });

    test('上万压缩成 万', () {
      expect(render(10000), '1万');
      expect(render(12000), '1.2万');
      expect(render(1234567), '123万');
    });
  });

  group('displayTags 筛选', () {
    List<String> tagsOf({
      List<String> tags = const <String>[],
      String sub = '',
      String category = '',
    }) =>
        JmAlbumSummary(
          id: '1',
          title: 'A',
          tags: tags,
          subCategoryTitle: sub,
          categoryTitle: category,
        ).displayTags;

    test('tags 优先，其次子分类，最多 2 个', () {
      expect(tagsOf(tags: ['同人', '漢化'], category: '單本'), <String>['同人', '漢化']);
      expect(
        tagsOf(tags: ['同人'], sub: '漢化', category: '單本'),
        <String>['同人', '漢化'],
      );
      expect(tagsOf(sub: '漢化', category: '單本'), <String>['漢化', '單本']);
      expect(tagsOf(category: '單本'), <String>['單本']);
    });

    test('过滤空值 / N/A / null / 重复', () {
      expect(tagsOf(tags: ['', '  ', 'N/A', 'n/a', 'null']), isEmpty);
      expect(tagsOf(tags: ['同人', '同人', ' 同人 ']), <String>['同人']);
      expect(tagsOf(tags: ['N/A'], category: '同人'), <String>['同人']);
    });

    test('过滤异常长文本', () {
      expect(tagsOf(tags: ['這是一個非常長的標籤文字']), isEmpty);
      expect(tagsOf(tags: ['八個字標籤長度測試喔']), isEmpty);
      expect(tagsOf(tags: ['八個字標籤長度']), <String>['八個字標籤長度']);
    });
  });
}
