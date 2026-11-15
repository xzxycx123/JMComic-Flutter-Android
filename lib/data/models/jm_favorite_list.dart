import 'jm_album_summary.dart';
import 'json_field.dart';

/// `GET /favorite` 的返回：`{count,total,list:[…]}`。
class JmFavoriteList {
  const JmFavoriteList({
    this.count = 0,
    this.total = 0,
    this.items = const <JmAlbumSummary>[],
    this.page = 1,
  });

  final int count;
  final int total;
  final List<JmAlbumSummary> items;
  final int page;

  bool get isEmpty => items.isEmpty;

  factory JmFavoriteList.fromJson(
    Map<String, dynamic> json, {
    int page = 1,
  }) {
    final list = asList(json['list'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmAlbumSummary.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return JmFavoriteList(
      count: asInt(json['count'], list.length),
      total: asInt(json['total'], list.length),
      items: list,
      page: page,
    );
  }

  static const JmFavoriteList empty = JmFavoriteList();
}
