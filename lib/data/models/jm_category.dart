import 'json_field.dart';

/// 二级分类（字段名实测为 `CID`）。
class JmSubCategory {
  const JmSubCategory({
    required this.id,
    required this.name,
    this.slug = '',
  });

  final String id;
  final String name;
  final String slug;

  factory JmSubCategory.fromJson(Map<String, dynamic> json) => JmSubCategory(
        id: asStringOr(json['CID'], asStringOr(json['id'], '')),
        name: asStringOr(json['name'], ''),
        slug: asStringOr(json['slug'], ''),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'CID': id,
        'name': name,
        'slug': slug,
      };
}

/// 顶层分类（`/categories`）。
class JmCategory {
  const JmCategory({
    required this.id,
    required this.name,
    this.slug = '',
    this.totalAlbums = 0,
    this.type = '',
    this.subs = const <JmSubCategory>[],
  });

  final String id;
  final String name;
  final String slug;
  final int totalAlbums;
  final String type;
  final List<JmSubCategory> subs;

  factory JmCategory.fromJson(Map<String, dynamic> json) => JmCategory(
        id: asStringOr(json['id'], ''),
        name: asStringOr(json['name'], ''),
        slug: asStringOr(json['slug'], ''),
        totalAlbums: asInt(json['total_albums']),
        type: asStringOr(json['type'], ''),
        subs: asList(json['sub_categories'])
            .map(asMap)
            .whereType<Map<String, dynamic>>()
            .map(JmSubCategory.fromJson)
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'slug': slug,
        'total_albums': totalAlbums,
        'type': type,
        'sub_categories': subs.map((sub) => sub.toJson()).toList(growable: false),
      };
}
