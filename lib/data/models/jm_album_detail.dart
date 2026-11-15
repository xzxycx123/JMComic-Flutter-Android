import 'jm_album_summary.dart';
import 'jm_chapter.dart';

/// `/album` 解析结果（对齐 `JmScript/data/Models.kt:JmAlbum`）。
class JmAlbumDetail {
  const JmAlbumDetail({
    required this.id,
    required this.title,
    this.seriesId = '0',
    this.totalPages = 0,
    this.chapters = const <JmChapterRef>[],
    this.author = '',
    this.description = '',
    this.tags = const <String>[],
    this.totalViews = 0,
    this.likes = 0,
    this.commentTotal = 0,
    this.related = const <JmAlbumSummary>[],
    this.isFavorite = false,
    this.liked = false,
  });

  final String id;
  final String title;
  final String seriesId;
  final int totalPages;

  /// 已按 `sort` 升序 + 同 `sort` 去重；`series` 为空时退化成只有自身一章。
  final List<JmChapterRef> chapters;

  final String author;
  final String description;
  final List<String> tags;
  final int totalViews;
  final int likes;
  final int commentTotal;
  final List<JmAlbumSummary> related;
  final bool isFavorite;
  final bool liked;

  bool get isSingleChapter => chapters.length <= 1;

  String get displayAuthor {
    final value = author.trim();
    return (value.isEmpty || value == 'N/A') ? '未知作者' : value;
  }

  String get displayTitle => title.trim().isEmpty ? 'JM$id' : title.trim();

  /// 用于详情页「已下载 / 未下载」与阅读器入口：单本取自身，多章取第一话。
  JmChapterRef get primaryChapter =>
      chapters.isEmpty
          ? JmChapterRef(id: id, sort: 1, title: title)
          : chapters.first;
}
