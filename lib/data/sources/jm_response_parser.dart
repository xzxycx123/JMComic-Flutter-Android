import '../../core/network/api_exception.dart';
import '../models/jm_album_detail.dart';
import '../models/jm_album_summary.dart';
import '../models/jm_category.dart';
import '../models/jm_chapter.dart';
import '../models/jm_comment.dart';
import '../models/jm_promote_module.dart';
import '../models/jm_search_page.dart';
import '../models/json_field.dart';

/// JSON -> 模型（移植 `JmScript/data/JmResponseParser.kt` 并扩展首页端点）。
///
/// 与 Kotlin 的差异（PLAN §5.3）：`/promote`、`/latest` 解密后是**顶层数组**，
/// 所以入口全部接 `dynamic`，先定型再解析。
abstract final class JmResponseParser {
  // ---------------------------------------------------------------- 专辑
  static JmAlbumDetail album(Map<String, dynamic> root, String requestedId) {
    final title = (asString(root['name']) ?? '').trim();
    final id = asString(root['id']) ?? requestedId;
    if (title.isEmpty) {
      throw JmContentException('未找到 JM$id 对应的漫画');
    }

    final chapters = asList(root['series'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final chapterId = asString(item['id']);
          if (chapterId == null || chapterId.isEmpty) return null;
          return JmChapterRef(
            id: chapterId,
            sort: asInt(item['sort'], 1),
            title: (asString(item['name']) ?? '').trim(),
          );
        })
        .whereType<JmChapterRef>()
        .toList(growable: false);

    final sorted = List<JmChapterRef>.from(chapters)
      ..sort((a, b) => a.sort.compareTo(b.sort));
    final seenSort = <int>{};
    final deduped = <JmChapterRef>[];
    for (final chapter in sorted) {
      if (seenSort.add(chapter.sort)) deduped.add(chapter);
    }

    return JmAlbumDetail(
      id: id,
      title: title,
      seriesId: asString(root['series_id']) ?? '0',
      totalPages: asInt(root['total_photos']),
      chapters: deduped.isEmpty
          ? <JmChapterRef>[JmChapterRef(id: id, sort: 1, title: title)]
          : deduped,
      author: asString(root['author']) ?? '',
      description: asString(root['description']) ?? '',
      tags: asTagList(root['tags']),
      totalViews: asInt(root['total_views']),
      likes: asInt(root['likes']),
      commentTotal: asInt(root['comment_total']),
      related: asList(root['related_list'])
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map(JmAlbumSummary.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      isFavorite: asBool(root['is_favorite']),
      liked: asBool(root['liked']),
    );
  }

  // ---------------------------------------------------------------- 章节
  static JmChapter chapter(Map<String, dynamic> root, JmChapterRef fallback) {
    final images = asStringList(root['images']);
    if (images.isEmpty) {
      throw JmContentException('章节 ${fallback.id} 没有可下载的图片');
    }
    final rawTitle = (asString(root['name']) ?? '').trim();
    return JmChapter(
      id: asString(root['id']) ?? fallback.id,
      title: rawTitle.isEmpty ? fallback.title : rawTitle,
      images: images,
      tags: asTagList(root['tags']),
    );
  }

  // ---------------------------------------------------------------- 域名发现
  static List<String> serverHosts(dynamic root) {
    final map = asMap(root);
    if (map == null) return const <String>[];
    return asStringList(map['Server']);
  }

  // ---------------------------------------------------------------- 首页
  static List<JmAlbumSummary> albumList(dynamic root) {
    return asList(root)
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmAlbumSummary.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static List<JmPromoteModule> promote(dynamic root) {
    return asList(root)
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmPromoteModule.fromJson)
        .where((module) => module.items.isNotEmpty)
        .toList(growable: false);
  }

  static List<JmCategory> categories(dynamic root) {
    final map = asMap(root);
    if (map == null) return const <JmCategory>[];
    return asList(map['categories'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmCategory.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  static JmSearchPage searchPage(
    dynamic root, {
    required int page,
    String query = '',
    String searchType = '',
  }) {
    final map = asMap(root);
    if (map == null) return JmSearchPage.empty;
    return JmSearchPage.fromJson(
      map,
      page: page,
      fallbackQuery: query,
      searchType: searchType,
    );
  }

  // ---------------------------------------------------------------- 评论
  /// `GET /forum` 解密后是 `{list:[...], total:"12"}`（total 是字符串）。
  static JmCommentPage comments(dynamic root, {required int page}) {
    final map = asMap(root);
    if (map == null) return JmCommentPage(page: page);
    final items = asList(map['list'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmComment.fromJson)
        .where((item) => item.content.isNotEmpty)
        .toList(growable: false);
    return JmCommentPage(
      items: items,
      total: asInt(map['total']),
      page: page,
    );
  }
}
