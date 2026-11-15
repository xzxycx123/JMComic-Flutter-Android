import 'json_field.dart';

/// 章节引用（`/album.series` 元素，或单本漫画退化成的那一章）。
class JmChapterRef {
  const JmChapterRef({
    required this.id,
    this.sort = 1,
    this.title = '',
  });

  final String id;
  final int sort;
  final String title;

  String get displayTitle => title.trim().isEmpty ? '第 $sort 话' : title.trim();

  factory JmChapterRef.fromJson(Map<String, dynamic> json) => JmChapterRef(
        id: asStringOr(json['id'], ''),
        sort: asInt(json['sort'], 1),
        title: asStringOr(json['name'], ''),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'sort': sort,
        'name': title,
      };

  @override
  bool operator ==(Object other) => other is JmChapterRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// `/chapter` 结果：`images` 是文件名数组，顺序即阅读顺序。
class JmChapter {
  const JmChapter({
    required this.id,
    required this.title,
    required this.images,
    this.tags = const <String>[],
  });

  final String id;
  final String title;
  final List<String> images;
  final List<String> tags;

  int get pageCount => images.length;

  factory JmChapter.fromJson(Map<String, dynamic> json) => JmChapter(
        id: asStringOr(json['id'], ''),
        title: asStringOr(json['name'], ''),
        images: asStringList(json['images']),
        tags: asTagList(json['tags']),
      );
}
