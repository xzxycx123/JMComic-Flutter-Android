import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/utils/author_name.dart';
import 'package:jm_comic/data/models/jm_album_detail.dart';
import 'package:jm_comic/data/models/jm_album_summary.dart';
import 'package:jm_comic/data/repositories/search_repository.dart';

void main() {
  group('normalizeAuthorName', () {
    test('剥掉半角 / 全角中括号', () {
      expect(normalizeAuthorName('[池下真上]'), '池下真上');
      expect(normalizeAuthorName('【池下真上】'), '池下真上');
      expect(normalizeAuthorName('［池下真上］'), '池下真上');
      expect(normalizeAuthorName('〔池下真上〕'), '池下真上');
      expect(normalizeAuthorName('  [池下真上]  '), '池下真上');
    });

    test('多作者各自去括号并收掉多余空白', () {
      expect(normalizeAuthorName('[柊咲] [川田曉生]'), '柊咲 川田曉生');
      expect(normalizeAuthorName('[柊咲], [川田曉生]'), '柊咲, 川田曉生');
      expect(normalizeAuthorName('[柊咲]、[川田曉生]'), '柊咲、川田曉生');
    });

    test('没有括号的作者保持原样', () {
      expect(normalizeAuthorName('池下真上'), '池下真上');
      expect(normalizeAuthorName('  池下真上  '), '池下真上');
      expect(normalizeAuthorName(''), '');
    });
  });

  group('作者名展示', () {
    test('列表卡片作者去掉中括号', () {
      const album = JmAlbumSummary(
        id: '1',
        title: '测试',
        author: '[池下真上]',
      );
      expect(album.authorName, '池下真上');
      expect(album.hasKnownAuthor, isTrue);
      expect(album.displayAuthor, '池下真上');
    });

    test('空括号 / 带括号的 N/A 视为未知作者', () {
      for (final author in <String>['[]', '【】', '[N/A]', '']) {
        final album = JmAlbumSummary(id: '1', title: '测试', author: author);
        expect(album.hasKnownAuthor, isFalse, reason: author);
        expect(album.displayAuthor, '未知作者', reason: author);
      }
    });

    test('详情作者去掉中括号', () {
      const album = JmAlbumDetail(id: '1', title: '测试', author: '【池下真上】');
      expect(album.authorName, '池下真上');
      expect(album.displayAuthor, '池下真上');
    });

    test('搜索结果补的作者meta 也去中括号', () {
      const detail = JmAlbumDetail(
        id: '1',
        title: '测试',
        author: '[池下真上]',
        tags: <String>['标签'],
      );
      final metadata = SearchAlbumMetadata.fromAlbum(detail);
      expect(metadata.author, '池下真上');
      expect(metadata.tags, <String>['标签']);
    });
  });
}
