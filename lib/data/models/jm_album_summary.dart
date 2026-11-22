import '../../core/utils/author_name.dart';
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
    this.likes = 0,
  });

  final String id;
  final String title;
  final String author;
  final List<String> tags;

  /// 剥掉 `[作者]` 这类中括号后的作者名（显示与作者搜索都用它）。
  String get authorName => normalizeAuthorName(author);

  bool get hasKnownAuthor {
    final value = authorName;
    return value.isNotEmpty && value.toUpperCase() != 'N/A';
  }

  final String categoryId;
  final String categoryTitle;
  final String subCategoryTitle;
  final int updateAt;
  final String addDate;
  final bool liked;
  final bool isFavorite;

  /// 「喜歡」数。列表接口（`/latest`、`/promote`、`/categories/filter`）不一定带
  /// 这个字段，缺失/无法解析时按 0 处理（卡片统一显示 `--`）。
  final int likes;

  String get displayTitle => title.trim().isEmpty ? 'JM$id' : title.trim();

  String get displayAuthor => hasKnownAuthor ? authorName : '未知作者';

  /// 通用标签兜底：`tags` 优先，其次子分类，最后一级分类。
  ///
  /// **卡片封面左上角不使用它**（那边走 [cardTags]，分类名不做兜底）；这里留给
  /// 没有 `/album` 补数机会、又需要一个可读标签的列表场景。
  /// 过滤空串 / `N/A` / `null` 之类的占位值、超过 [_maxTagRunes] 个字的异常长文本
  /// 与重复项，最多保留 [_maxCardTags] 个。
  List<String> get displayTags {
    final result = <String>[];
    for (final raw in <String>[...tags, subCategoryTitle, categoryTitle]) {
      final label = _normalizeTag(raw);
      if (label == null || result.contains(label)) continue;
      result.add(label);
      if (result.length >= _maxCardTags) break;
    }
    return List<String>.unmodifiable(result);
  }

  /// 卡片左下角喜欢数：无计数统一 `--`；上万压缩成「1.2万」。
  String get displayLikes {
    if (likes <= 0) return noLikeCount;
    if (likes < 10000) return '$likes';
    final wan = likes / 10000;
    final fixed = wan >= 100 ? wan.toStringAsFixed(0) : wan.toStringAsFixed(1);
    final trimmed =
        fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
    return '$trimmed万';
  }

  /// 没有喜欢数时的统一占位（首页卡片 / 后续复用方都用这个常量）。
  static const String noLikeCount = '--';

  /// 封面左上角的分类名（`同人` / `單本` / `English Manga` …）。
  ///
  /// 只过滤空串 / `N/A` 这类占位值；长度上限比标签宽松（`English Manga` 有 13 个字）。
  /// 拿不到分类就不画角标。
  String? get cardCategory {
    final label = categoryTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label.isEmpty) return null;
    if (_placeholderTags.contains(label.toLowerCase())) return null;
    if (label.runes.length > _maxCategoryRunes) return null;
    return label;
  }

  /// 作者名下方的作品标签：来自 `/album.tags`（列表接口没有 tags）。
  ///
  /// 语言 / 翻译类标签（`中文` / `漢化` / `日語` …）直接跳过，让 `伪娘` / `扶她` /
  /// `百合` 这类内容标签优先露出；最多 [_maxCardTags] 个。**拿不到 tags 时为空**，
  /// 不拿分类名兜底 —— 「同人」是分类，画在封面左上角。
  List<String> get cardTags {
    final result = <String>[];
    for (final raw in tags) {
      final label = _normalizeTag(raw);
      if (label == null) continue;
      if (_languageTags.contains(label.toLowerCase())) continue;
      if (result.contains(label)) continue;
      result.add(label);
      if (result.length >= _maxCardTags) break;
    }
    return List<String>.unmodifiable(result);
  }

  /// 卡片标签的原始来源（用于判断是否已从 `/album` 补过数）。
  bool get hasTags => tags.isNotEmpty;

  static const int _maxCardTags = 2;
  static const int _maxCategoryRunes = 20;
  static const int _maxTagRunes = 8;

  /// 语言 / 翻译类标签：不是作品内容，排在内容标签之后。
  static const Set<String> _languageTags = <String>{
    '中文',
    '漢化',
    '汉化',
    '日語',
    '日语',
    '英文',
    'english',
    '翻譯',
    '翻译',
  };

  static const Set<String> _placeholderTags = <String>{
    'n/a',
    'na',
    'null',
    'none',
    'undefined',
    '-',
    '--',
  };

  static String? _normalizeTag(String raw) {
    final label = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (label.isEmpty) return null;
    if (_placeholderTags.contains(label.toLowerCase())) return null;
    if (label.runes.length > _maxTagRunes) return null;
    return label;
  }

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
      likes: _asLikeCount(
        json['likes'] ??
            json['like_count'] ??
            json['likes_count'] ??
            json['like'],
      ),
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
        'likes': likes,
      };

  JmAlbumSummary copyWith({
    bool? liked,
    bool? isFavorite,
    int? likes,
    List<String>? tags,
  }) =>
      JmAlbumSummary(
        id: id,
        title: title,
        author: author,
        tags: tags ?? this.tags,
        categoryId: categoryId,
        categoryTitle: categoryTitle,
        subCategoryTitle: subCategoryTitle,
        updateAt: updateAt,
        addDate: addDate,
        liked: liked ?? this.liked,
        isFavorite: isFavorite ?? this.isFavorite,
        likes: likes ?? this.likes,
      );

  @override
  bool operator ==(Object other) => other is JmAlbumSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// 喜欢数解析：兼容 `4321` / `"4321"` / `"4,321"` / `"1.2k"` / `"1.2万"`，
/// 缺失、负数、乱码一律按 0。
int _asLikeCount(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value <= 0 ? 0 : value;
  if (value is num) return value.toInt() <= 0 ? 0 : value.toInt();
  if (value is bool) return 0;
  final text = value.toString().replaceAll(RegExp(r'[,\s+]'), '').trim();
  if (text.isEmpty) return 0;
  final match =
      RegExp(r'^([0-9]+(?:\.[0-9]+)?)([kKmMwW千万元]?)$').firstMatch(text);
  if (match == null) return 0;
  final base = double.tryParse(match.group(1)!) ?? 0;
  final unit = (match.group(2) ?? '').toLowerCase();
  final factor = switch (unit) {
    'k' || '千' => 1000.0,
    'm' => 1000000.0,
    'w' || '万' => 10000.0,
    _ => 1.0,
  };
  final count = (base * factor).round();
  return count <= 0 ? 0 : count;
}
