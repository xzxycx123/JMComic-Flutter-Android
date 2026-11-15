import 'dart:convert';

import 'json_field.dart';
import 'jm_album_summary.dart';
import 'jm_category.dart';
import 'jm_promote_module.dart';

/// 首页轮播项：模块首项 + 模块标题。
class PromoteBanner {
  const PromoteBanner({
    required this.album,
    required this.moduleTitle,
    this.moduleId = '',
  });

  final JmAlbumSummary album;
  final String moduleTitle;
  final String moduleId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'album': album.toJson(),
        'moduleTitle': moduleTitle,
        'moduleId': moduleId,
      };

  factory PromoteBanner.fromJson(Map<String, dynamic> json) => PromoteBanner(
        album: JmAlbumSummary.fromJson(asMap(json['album']) ?? const <String, dynamic>{}),
        moduleTitle: asStringOr(json['moduleTitle'], ''),
        moduleId: asStringOr(json['moduleId'], ''),
      );
}

/// 首页聚合结果（PLAN §6.1）。
class HomeFeed {
  const HomeFeed({
    required this.banners,
    required this.modules,
    required this.latest,
    required this.grid,
    required this.categories,
    this.gridPage = 1,
    this.gridTotal = 0,
    this.gridTotalCapped = false,
    this.gridExhausted = false,
    this.updatedAt,
    this.fromCache = false,
    this.partialErrors = const <String>[],
  });

  final List<PromoteBanner> banners;
  final List<JmPromoteModule> modules;
  final List<JmAlbumSummary> latest;
  final List<JmAlbumSummary> grid;
  final List<JmCategory> categories;
  final int gridPage;
  final int gridTotal;

  /// 服务端 total 触顶（10000）时为 true，UI 不显示精确总数。
  final bool gridTotalCapped;

  /// 已经翻到底（服务端返回空页），UI 停止触发加载。
  final bool gridExhausted;
  final DateTime? updatedAt;
  final bool fromCache;

  /// 分区级失败原因（只隐藏该分区，不整页报错）。
  final List<String> partialErrors;

  bool get isEmpty => modules.isEmpty && latest.isEmpty && grid.isEmpty;

  HomeFeed copyWith({
    List<PromoteBanner>? banners,
    List<JmPromoteModule>? modules,
    List<JmAlbumSummary>? latest,
    List<JmAlbumSummary>? grid,
    List<JmCategory>? categories,
    int? gridPage,
    int? gridTotal,
    bool? gridTotalCapped,
    bool? gridExhausted,
    DateTime? updatedAt,
    bool? fromCache,
    List<String>? partialErrors,
  }) =>
      HomeFeed(
        banners: banners ?? this.banners,
        modules: modules ?? this.modules,
        latest: latest ?? this.latest,
        grid: grid ?? this.grid,
        categories: categories ?? this.categories,
        gridPage: gridPage ?? this.gridPage,
        gridTotal: gridTotal ?? this.gridTotal,
        gridTotalCapped: gridTotalCapped ?? this.gridTotalCapped,
        gridExhausted: gridExhausted ?? this.gridExhausted,
        updatedAt: updatedAt ?? this.updatedAt,
        fromCache: fromCache ?? this.fromCache,
        partialErrors: partialErrors ?? this.partialErrors,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'banners': banners.map((item) => item.toJson()).toList(growable: false),
        'modules': modules.map((item) => item.toJson()).toList(growable: false),
        'latest': latest.map((item) => item.toJson()).toList(growable: false),
        'grid': grid.map((item) => item.toJson()).toList(growable: false),
        'categories': categories.map((item) => item.toJson()).toList(growable: false),
        'gridPage': gridPage,
        'gridTotal': gridTotal,
        'gridTotalCapped': gridTotalCapped,
        'gridExhausted': gridExhausted,
        'updatedAt': updatedAt?.millisecondsSinceEpoch ?? 0,
        'partialErrors': partialErrors,
      };

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> mapsOf(dynamic value) => asList(value)
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final stamp = asInt(json['updatedAt']);
    return HomeFeed(
      banners: mapsOf(json['banners'])
          .map(PromoteBanner.fromJson)
          .where((item) => item.album.id.isNotEmpty)
          .toList(growable: false),
      modules: mapsOf(json['modules'])
          .map(JmPromoteModule.fromJson)
          .where((item) => item.items.isNotEmpty)
          .toList(growable: false),
      latest: mapsOf(json['latest'])
          .map(JmAlbumSummary.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      grid: mapsOf(json['grid'])
          .map(JmAlbumSummary.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      categories: mapsOf(json['categories'])
          .map(JmCategory.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: false),
      gridPage: asInt(json['gridPage'], 1),
      gridTotal: asInt(json['gridTotal']),
      gridTotalCapped: asBool(json['gridTotalCapped']),
      gridExhausted: asBool(json['gridExhausted']),
      updatedAt: stamp <= 0 ? null : DateTime.fromMillisecondsSinceEpoch(stamp),
      partialErrors: asStringList(json['partialErrors']),
    );
  }

  String encode() => jsonEncode(toJson());

  static HomeFeed? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final map = asMap(decoded);
      if (map == null) return null;
      return HomeFeed.fromJson(map);
    } catch (_) {
      return null;
    }
  }
}
