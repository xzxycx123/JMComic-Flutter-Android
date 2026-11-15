import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/data/models/jm_chapter.dart';
import 'package:jm_comic/data/sources/jm_response_parser.dart';

import '../helpers/fixtures.dart';

void main() {
  group('album', () {
    test('章节按 sort 升序 + 同 sort 去重', () {
      final root = <String, dynamic>{
        'id': 100,
        'name': 'Test Comic',
        'series_id': '0',
        'total_photos': '3',
        'series': <Map<String, dynamic>>[
          {'id': '102', 'sort': '2', 'name': 'Second'},
          {'id': '101', 'sort': '1', 'name': 'First'},
          {'id': '103', 'sort': '2', 'name': 'Duplicate sort'},
        ],
      };
      final album = JmResponseParser.album(root, '100');
      expect(album.title, 'Test Comic');
      expect(album.totalPages, 3);
      expect(album.chapters.map((chapter) => chapter.id).toList(), <String>['101', '102']);
    });

    test('series 为空时退化成单章', () {
      final root = <String, dynamic>{
        'id': 123,
        'name': 'Single',
        'series_id': '0',
        'total_photos': '1',
        'series': <dynamic>[],
      };
      final album = JmResponseParser.album(root, '123');
      expect(album.chapters.map((chapter) => chapter.id).toList(), <String>['123']);
    });

    test('fixture 详情可解析（tags / stats / related）', () {
      final album = JmResponseParser.album(Fixtures.album(), '350234');
      expect(album.id, '350234');
      expect(album.totalPages, 19);
      expect(album.tags, <String>['同人', '漢化']);
      expect(album.related.length, 1);
      expect(album.primaryChapter.id, '350234');
    });
  });

  group('chapter', () {
    test('保持图片原顺序，空标题回退 fallback', () {
      const fallback = JmChapterRef(id: '123', sort: 1, title: 'Fallback');
      final root = <String, dynamic>{
        'id': 123,
        'name': '',
        'images': <String>['00002.webp', '00001.webp'],
      };
      final chapter = JmResponseParser.chapter(root, fallback);
      expect(chapter.title, 'Fallback');
      expect(chapter.images, <String>['00002.webp', '00001.webp']);
    });

    test('images 为空抛 JmContentException', () {
      const fallback = JmChapterRef(id: '123', sort: 1, title: 'Fallback');
      expect(
        () => JmResponseParser.chapter(<String, dynamic>{'id': 123, 'images': <dynamic>[]}, fallback),
        throwsA(isA<JmContentException>()),
      );
    });

    test('fixture 章节图片数', () {
      final chapter = JmResponseParser.chapter(
        Fixtures.chapter(),
        const JmChapterRef(id: '350234', sort: 1, title: ''),
      );
      expect(chapter.pageCount, 3);
    });
  });

  group('首页端点', () {
    test('promote 顶层数组 → 模块列表', () {
      final modules = JmResponseParser.promote(Fixtures.promote());
      expect(modules.length, 2);
      expect(modules.first.title, '連載更新');
      expect(modules.first.items.first.categoryTitle, '單本');
    });

    test('latest 顶层数组 → 列表项', () {
      final albums = JmResponseParser.albumList(Fixtures.latest());
      expect(albums.length, 4);
      expect(albums.first.id, '1490663');
      expect(albums.first.displayAuthor, '未知作者');
    });

    test('categories 字段与子分类 CID', () {
      final categories = JmResponseParser.categories(Fixtures.categories());
      expect(categories.length, 10);
      final doujin = categories.firstWhere((item) => item.id == '1');
      expect(doujin.totalAlbums, 357417);
      expect(doujin.subs.first.id, '1');
      expect(doujin.subs.first.name, '漢化');
    });

    test('filter → total 触顶标记由上层处理', () {
      final page = JmResponseParser.searchPage(Fixtures.filter(), page: 1);
      expect(page.total, 10000);
      expect(page.content.length, 3);
      expect(page.hasMoreWith(80), isTrue);
    });
  });
}
