import 'json_field.dart';

/// 列表项（首页 / 分类 / 搜索共用）。
///
/// `/promote`、`/latest`、`/categories/filter`、`/search` 的 content 元素同构。
class JmAlbumSummary {
  const JmAlbumSummary({
    required this.id,
    required this.title,
    this.author = 'N/A',
    this.tags = const <String>[],
    this.categoryId = '0',
    this.categoryTitle = '',
    this.subCategoryTitle = '',
    this.updateAt = 0,
    this.addDate = '',
    this.liked = false,
    this.isFavorite = false,
  });

  final String id;
  final String title;
  final String author;
  final List<String> tags;

  bool get hasKnownAuthor {
    final value = author.trim();
    return value.isNotEmpty && value.toUpperCase() != 'N/A';
  }

  final String categoryId;
  final String categoryTitle;
  final String subCategoryTitle;
  final int updateAt;
  final String addDate;
  final bool liked;
  final bool isFavorite;

  String get displayTitle => title.trim().isEmpty ? 'JM$id' : title.trim();

  String get displayAuthor => hasKnownAuthor ? author.trim() : '未知作者';

  DateTime? get updatedTime => updateAt <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(updateAt * 1000);

  /// 7 天内上架（列表接口的 `adddate` 是 `yyyy-MM-dd`），用于卡片的 NEW 角标。
  bool get isNew {
    final date = DateTime.tryParse(addDate);
    if (date == null) return false;
    return DateTime.now().difference(date).inDays.abs() <= 7;
  }

  factory JmAlbumSummary.fromJson(Map<String, dynamic> json) {
    final category = asMap(json['category']);
    final categorySub = asMap(json['category_sub']);
    return JmAlbumSummary(
      id: asStringOr(json['id'], ''),
      title: asStringOr(json['name'], ''),
      author: asStringOr(json['author'], 'N/A'),
      tags: List.unmodifiable(asTagList(json['tags'] ?? json['tag']).toSet()),
      categoryId: asStringOr(category?['id'], '0'),
      categoryTitle: asStringOr(category?['title'], ''),
      subCategoryTitle: asStringOr(categorySub?['title'], ''),
      updateAt: asInt(json['update_at']),
      addDate: asStringOr(json['adddate'], ''),
      liked: asBool(json['liked']),
      isFavorite: asBool(json['is_favorite']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': title,
        'author': author,
        if (tags.isNotEmpty) 'tags': tags,
        'category': <String, dynamic>{'id': categoryId, 'title': categoryTitle},
        'category_sub': <String, dynamic>{
          'id': null,
          'title': subCategoryTitle.isEmpty ? null : subCategoryTitle,
        },
        'update_at': updateAt,
        'adddate': addDate,
        'liked': liked,
        'is_favorite': isFavorite,
      };

  JmAlbumSummary copyWith({bool? liked, bool? isFavorite}) => JmAlbumSummary(
        id: id,
        title: title,
        author: author,
        tags: tags,
        categoryId: categoryId,
        categoryTitle: categoryTitle,
        subCategoryTitle: subCategoryTitle,
        updateAt: updateAt,
        addDate: addDate,
        liked: liked ?? this.liked,
        isFavorite: isFavorite ?? this.isFavorite,
      );

  @override
  bool operator ==(Object other) => other is JmAlbumSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
