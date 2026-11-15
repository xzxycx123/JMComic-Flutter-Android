import 'json_field.dart';
import 'jm_album_summary.dart';

/// `/promote` 的一个首页模块（横滑分节 / 轮播来源）。
class JmPromoteModule {
  const JmPromoteModule({
    required this.id,
    required this.title,
    required this.type,
    required this.filterVal,
    required this.items,
  });

  final String id;
  final String title;
  final String type;
  final String filterVal;
  final List<JmAlbumSummary> items;

  JmAlbumSummary? get first => items.isEmpty ? null : items.first;

  factory JmPromoteModule.fromJson(Map<String, dynamic> json) {
    final content = asList(json['content'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmAlbumSummary.fromJson)
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    return JmPromoteModule(
      id: asStringOr(json['id'], ''),
      title: asStringOr(json['title'], ''),
      type: asStringOr(json['type'], ''),
      filterVal: asStringOr(json['filter_val'], ''),
      items: content,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'type': type,
        'filter_val': filterVal,
        'content': items.map((item) => item.toJson()).toList(growable: false),
      };
}
