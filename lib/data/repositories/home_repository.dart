import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
import '../local/hive_init.dart';
import '../models/home_feed.dart';
import '../models/jm_album_summary.dart';
import '../models/jm_category.dart';
import '../models/jm_promote_module.dart';
import '../models/jm_search_page.dart';
import '../sources/jm_api_client.dart';

/// 首页聚合 + 分页 + 缓存 + 降级（PLAN §6.1/§6.2）。
///
/// 分类筛选一律用 **slug**（[JmCategory.slug]）：`/categories/filter` 的 `c`
/// 传数字 id 时服务端会忽略并退回默认榜，这正是「点标签没反应」的根因。
class HomeRepository {
  HomeRepository({
    required JmApi api,
    Box<dynamic>? cacheBox,
    Future<HomeFeed?> Function()? htmlFallback,
  })  : _api = api,
        _cacheBox = cacheBox,
        _htmlFallback = htmlFallback;

  static const String _keyFeed = 'feed';

  final JmApi _api;
  final Box<dynamic>? _cacheBox;
  final Future<HomeFeed?> Function()? _htmlFallback;

  /// 冷启动：先给缓存（标 fromCache），后台再刷。
  HomeFeed? readCache() => readCachedFeed(_cacheBox);

  /// 不依赖 JmApi 的缓存读取：首页可以在网络/引导就绪前先把上次的内容画出来。
  static HomeFeed? readCachedFeed(Box<dynamic>? box) {
    final raw = box?.get(_keyFeed);
    if (raw is! Map) return null;
    final map = raw.map((key, value) => MapEntry('$key', value));
    final payload = map['payload'];
    if (payload is! String) return null;
    final feed = HomeFeed.decode(payload);
    if (feed == null) return null;
    final cachedAt = map['cachedAt'];
    final stamp = cachedAt is int ? cachedAt : 0;
    return feed.copyWith(
      fromCache: true,
      updatedAt: stamp <= 0 ? feed.updatedAt : DateTime.fromMillisecondsSinceEpoch(stamp),
    );
  }

  bool cacheExpired() {
    final raw = _cacheBox?.get(_keyFeed);
    if (raw is! Map) return true;
    final stamp = raw['cachedAt'];
    if (stamp is! int || stamp <= 0) return true;
    final cachedAt = DateTime.fromMillisecondsSinceEpoch(stamp);
    return DateTime.now().difference(cachedAt) > AppConfig.feedCacheTtl;
  }

  Future<void> _writeCache(HomeFeed feed) async {
    final box = _cacheBox;
    if (box == null) return;
    await box.put(_keyFeed, <String, dynamic>{
      'payload': feed.encode(),
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// 拉首页 feed：四个端点各自容错，全挂才整页报错。
  ///
  /// [categorySlug] 为空 = 不过滤（最新A漫）。[persistCache] 默认只对默认首页开：
  /// 分类页不写磁盘缓存，否则冷启动会把「上次点的分类」当成首页画出来。
  Future<HomeFeed> fetchFeed({
    bool preferCache = false,
    String categorySlug = '',
    AlbumOrder order = AlbumOrder.latestUpdate,
    bool? persistCache,
  }) async {
    final persist = persistCache ?? categorySlug.isEmpty;
    final cached = preferCache ? readCache() : null;
    if (cached != null && !cacheExpired()) return cached;

    final errors = <String>[];
    List<JmPromoteModule> modules = const <JmPromoteModule>[];
    List<JmAlbumSummary> latest = const <JmAlbumSummary>[];
    List<JmCategory> categories = const <JmCategory>[];
    List<JmAlbumSummary> grid = const <JmAlbumSummary>[];
    var total = 0;

    try {
      modules = await _api.fetchPromote();
    } catch (error) {
      errors.add('推荐分区加载失败');
      Log.w('fetchPromote 失败：$error');
    }

    try {
      latest = await _api.fetchLatest(page: 1);
    } catch (error) {
      errors.add('最新上架加载失败');
      Log.w('fetchLatest 失败：$error');
    }

    try {
      categories = await _api.fetchCategories();
    } catch (error) {
      errors.add('分类加载失败');
      Log.w('fetchCategories 失败：$error');
    }

    try {
      final page = await _api.fetchFilter(
        page: 1,
        categorySlug: categorySlug,
        order: order,
      );
      grid = page.content;
      total = page.total;
    } catch (error) {
      errors.add('瀑布流加载失败');
      Log.w('fetchFilter 失败：$error');
    }

    if (modules.isEmpty && latest.isEmpty && grid.isEmpty) {
      final fallback = await _htmlFallback?.call();
      if (fallback != null) {
        return fallback.copyWith(categories: _categoriesWithFallback(categories));
      }
      if (cached != null) {
        return cached.copyWith(partialErrors: const <String>['网络不可用，显示缓存内容']);
      }
      throw JmApiException(
        errors.isEmpty ? '首页加载失败' : errors.join(' · '),
        network: true,
      );
    }

    final feed = HomeFeed(
      banners: _buildBanners(modules),
      modules: modules,
      latest: latest.take(40).toList(growable: false),
      grid: grid,
      categories: _categoriesWithFallback(categories),
      gridPage: 1,
      gridTotal: total,
      gridTotalCapped: total >= AppConfig.maxServerTotal,
      updatedAt: DateTime.now(),
      partialErrors: errors,
    );
    if (persist) await _writeCache(feed);
    return feed;
  }

  /// 只拉第一页瀑布流：分类标签用（1 次请求，不重复取 promote/latest/categories）。
  Future<JmSearchPage> categoryPage({
    String categorySlug = '',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) =>
      _api.fetchFilter(page: 1, categorySlug: categorySlug, order: order);

  /// 加载下一页瀑布流；失败时返回原 feed（UI 底部给"重试"条）。
  ///
  /// 服务端返回空页即视为到底（`o=mv_t` 这类分类第 3 页就会空），
  /// 置 `gridExhausted` 后不再发请求。
  Future<HomeFeed> loadMore(
    HomeFeed current, {
    String categorySlug = '',
    AlbumOrder order = AlbumOrder.latestUpdate,
    bool? persistCache,
  }) async {
    final persist = persistCache ?? categorySlug.isEmpty;
    if (current.gridExhausted) return current;
    if (current.gridTotal >= AppConfig.maxServerTotal &&
        current.gridPage >= (AppConfig.maxServerTotal / AppConfig.pageSize).ceil()) {
      return current.copyWith(gridExhausted: true);
    }
    final nextPage = current.gridPage + 1;
    final page = await _api.fetchFilter(
      page: nextPage,
      categorySlug: categorySlug,
      order: order,
    );
    if (page.content.isEmpty) {
      final updated = current.copyWith(gridPage: nextPage, gridExhausted: true);
      if (persist) await _writeCache(updated);
      return updated;
    }
    final merged = mergeUnique(current.grid, page.content);
    final updated = current.copyWith(
      grid: merged,
      gridPage: nextPage,
      gridTotal: page.total > 0 ? page.total : current.gridTotal,
      gridTotalCapped: page.total >= AppConfig.maxServerTotal,
      gridExhausted: false,
      updatedAt: DateTime.now(),
      partialErrors: const <String>[],
    );
    if (persist) await _writeCache(updated);
    return updated;
  }

  /// 按 id 去重 + 保序（`/latest` 与 `filter` 有重叠）。
  static List<JmAlbumSummary> mergeUnique(
    List<JmAlbumSummary> head,
    List<JmAlbumSummary> tail,
  ) {
    final seen = <String>{};
    final result = <JmAlbumSummary>[];
    for (final album in <JmAlbumSummary>[...head, ...tail]) {
      if (album.id.isEmpty) continue;
      if (seen.add(album.id)) result.add(album);
    }
    return result;
  }

  static List<PromoteBanner> _buildBanners(List<JmPromoteModule> modules) {
    final banners = <PromoteBanner>[];
    for (final module in modules.take(6)) {
      final album = module.first;
      if (album == null) continue;
      banners.add(
        PromoteBanner(
          album: album,
          moduleTitle: module.title,
          moduleId: module.id,
        ),
      );
    }
    return banners;
  }

  /// 分类接口失败时用固定的 10 个顶层分类兜底（PLAN §5.4），slug 用于筛选。
  static List<JmCategory> _categoriesWithFallback(List<JmCategory> categories) {
    if (categories.isNotEmpty) return categories;
    return JmCategoryFallback.items
        .map((item) => JmCategory(id: item.id, name: item.name, slug: item.slug))
        .toList(growable: false);
  }
}

/// 首页缓存的原始 JSON（调试 / 导出用）。
String encodeFeedForDebug(HomeFeed feed) => jsonEncode(feed.toJson());

/// 缓存 box 名（供 provider 取）。
const String homeFeedBoxName = HiveBoxes.feedCache;
