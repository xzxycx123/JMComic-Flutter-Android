import 'json_field.dart';
import 'jm_album_summary.dart';

/// `/categories/filter` 与 `/search` 共用的分页结果。
class JmSearchPage {
  const JmSearchPage({
    required this.query,
    required this.total,
    required this.content,
    required this.page,
    this.redirectAid,
    this.searchType = '',
  });

  final String query;
  final int total;
  final List<JmAlbumSummary> content;
  final int page;

  /// 命中车号时服务端下发的直达 id（`/search` 双保险）。
  final String? redirectAid;
  final String searchType;

  bool get isEmpty => content.isEmpty;

  /// 服务端 total 有上限（实测 10000），到顶后按"还有更多"处理但不再假装无限。
  bool hasMoreWith(int pageSize) =>
      content.isNotEmpty && (page - 1) * pageSize + content.length < total;

  factory JmSearchPage.fromJson(
    Map<String, dynamic> json, {
    required int page,
    String fallbackQuery = '',
    String searchType = '',
  }) {
    final content = asList(json['content'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmAlbumSummary.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return JmSearchPage(
      query: asStringOr(json['search_query'], fallbackQuery),
      total: asInt(json['total'], content.length),
      content: content,
      page: page,
      redirectAid: asString(json['redirect_aid']),
      searchType: asStringOr(json['search_type'], searchType),
    );
  }

  static const JmSearchPage empty = JmSearchPage(
    query: '',
    total: 0,
    content: <JmAlbumSummary>[],
    page: 1,
  );
}
