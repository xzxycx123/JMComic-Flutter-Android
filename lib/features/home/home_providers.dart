import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
import '../../core/utils/logger.dart';
import '../../data/local/hive_init.dart';
import '../../data/models/home_feed.dart';
import '../../data/models/jm_album_summary.dart';
import '../../data/models/jm_category.dart';
import '../../data/repositories/home_repository.dart';

/// 分类选择：一级分类 id + 二级 slug（空串 = 该分类全部）。
///
/// `/categories/filter` 的 `c` 只认 slug，二级筛选要靠 `父slug_子slug` 拼出来
/// （实测 `c=doujin_chinese` 生效，`c=doujin&o=chinese` 会被忽略）。
typedef CategorySelection = ({String id, String sub});

/// 当前选中的分类（chip）。`id` 为 `0` / 空 = 最新A漫（不过滤）。
final StateProvider<CategorySelection> selectedCategoryProvider =
    StateProvider<CategorySelection>((ref) => (id: '0', sub: ''));

/// 当前排序。
final StateProvider<AlbumOrder> albumOrderProvider =
    StateProvider<AlbumOrder>((ref) => AlbumOrder.latestUpdate);

/// 下一页加载失败的原因（UI 底部给"重试"条，不弹全屏错误）。
final StateProvider<String?> loadMoreErrorProvider =
    StateProvider<String?>((ref) => null);

/// 是否正在加载下一页（分类首屏加载也复用它，底部显示转圈）。
final StateProvider<bool> loadingMoreProvider =
    StateProvider<bool>((ref) => false);

/// 标签页（分类 + 二级 + 排序）组合键：首页内存缓存按它分桶。
typedef FeedKey = ({String category, String sub, AlbumOrder order});

final AsyncNotifierProvider<HomeFeedNotifier, HomeFeed> homeFeedProvider =
    AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

/// 首页 feed：**内存里按标签页缓存**，切回来先出缓存再后台刷新。
///
/// 分类筛选走 `/categories/filter?c=<slug>`：
/// * 数字分类 id 服务端不认（`c=1` 与 `c=0` 返回同一份榜），所以每个 chip 都要
///   用 `/categories` 里的 [JmCategory.slug] 去查；
/// * 二级分类拼成 `父slug_子slug`（`doujin_chinese`），传 `sub.CID` 或 `o=` 都无效；
/// * 切分类只打 1 次 `/categories/filter`，轮播 / 分节 / 分类条沿用上次整页结果
///   （UI 在筛选态本来也不展示这些全局内容）；
/// * 只有默认首页（最新A漫）写磁盘缓存，避免冷启动把上次点的分类当成首页。
class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  final Map<FeedKey, HomeFeed> _feeds = <FeedKey, HomeFeed>{};
  final Map<FeedKey, DateTime> _stamps = <FeedKey, DateTime>{};

  /// 最近一次整页结果（含 promote / latest / categories），给分类页复用。
  HomeFeed? _chrome;
  FeedKey? _current;
  bool _disposed = false;
  bool _prewarmed = false;
  bool _warming = false;
  Timer? _prewarmTimer;

  @override
  Future<HomeFeed> build() async {
    ref.onDispose(() {
      _disposed = true;
      _prewarmTimer?.cancel();
    });

    ref.listen<CategorySelection>(selectedCategoryProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_switchTo(next, ref.read(albumOrderProvider)));
    });
    ref.listen<AlbumOrder>(albumOrderProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_switchTo(ref.read(selectedCategoryProvider), next));
    });

    final selection = ref.read(selectedCategoryProvider);
    final order = ref.read(albumOrderProvider);
    final key = _keyOf(selection, order);
    _current = key;

    // 冷启动：先把「上次的主页」直接画出来（不看 TTL，也不等网络/引导），
    // 再后台拉新并在成功后整体替换（PLAN §6.2 的加强版）。
    if (_isDefault(key)) {
      final cached = HomeRepository.readCachedFeed(
        Hive.box<dynamic>(HiveBoxes.feedCache),
      );
      if (cached != null) {
        _remember(key, cached);
        _chrome = cached;
        unawaited(_load(key));
        return cached;
      }
    }

    final repository = await ref.watch(homeRepositoryProvider.future);
    final feed = await repository.fetchFeed(
      categorySlug: _slugFor(key),
      order: order,
      persistCache: _isDefault(key),
    );
    _remember(key, feed);
    _chrome = feed;
    unawaited(_prewarm(key, feed));
    // 首屏还在路上时用户已经点了别的分类：别把默认首页盖回去。
    final current = state.valueOrNull;
    if (_current != key && current != null) return current;
    return feed;
  }

  static bool _isDefault(FeedKey key) =>
      key.category == '0' || key.category.isEmpty;

  FeedKey _keyOf(CategorySelection selection, AlbumOrder order) =>
      (category: selection.id, sub: selection.sub, order: order);

  /// `/categories/filter?c=` 的取值：`slug` 或 `父slug_子slug`。
  String _slugFor(FeedKey key) {
    final base = _slugOf(key.category);
    if (base.isEmpty || key.sub.isEmpty) return base;
    return '${base}_${key.sub}';
  }

  /// 分类 id 换成 slug（服务端筛选参数）。分类表还没到就用固定兜底表。
  String _slugOf(String categoryId) {
    if (categoryId.isEmpty || categoryId == '0') return '';
    for (final category in _chrome?.categories ?? const <JmCategory>[]) {
      if (category.id == categoryId && category.slug.isNotEmpty) {
        return category.slug;
      }
    }
    for (final item in JmCategoryFallback.items) {
      if (item.id == categoryId) return item.slug;
    }
    return '';
  }

  void _remember(FeedKey key, HomeFeed feed) {
    _feeds[key] = feed;
    _stamps[key] = DateTime.now();
  }

  /// 可取消的等待：provider 销毁时取消计时器，别让 widget 测试留着 pending timer。
  Future<void> _sleep(Duration duration) {
    final completer = Completer<void>();
    _prewarmTimer?.cancel();
    _prewarmTimer = Timer(duration, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  /// 切换标签页：有缓存先出缓存，再按 TTL 决定是否后台刷新。
  Future<void> _switchTo(CategorySelection selection, AlbumOrder order) async {
    if (_disposed) return;
    final key = _keyOf(selection, order);
    if (_current == key) return;
    _current = key;
    ref.read(loadMoreErrorProvider.notifier).state = null;
    // 上一次切换可能还在等网络：先把翻页/加载态清掉，避免转圈卡在缓存页上。
    ref.read(loadingMoreProvider.notifier).state = false;

    final cached = _feeds[key];
    if (cached != null) {
      // 关键：直接复用上次的数据，不闪骨架屏、不重置网格。
      state = AsyncValue<HomeFeed>.data(cached);
      final stamp = _stamps[key];
      final fresh = stamp != null &&
          DateTime.now().difference(stamp) < AppConfig.categoryCacheTtl;
      if (!fresh) unawaited(_load(key));
      return;
    }

    // 先出一层「空网格 + 沿用上次的分节/分类条」的壳：分类 chip 不会整页消失，
    // 底部转圈表示正在按新分类重查，切完再整体替换。
    final shell = _shellFor(key);
    if (shell != null) {
      state = AsyncValue<HomeFeed>.data(shell);
      ref.read(loadingMoreProvider.notifier).state = true;
      try {
        await _load(key);
      } finally {
        if (!_disposed && _current == key) {
          ref.read(loadingMoreProvider.notifier).state = false;
        }
      }
      return;
    }

    state = const AsyncValue<HomeFeed>.loading();
    await _load(key);
  }

  /// 分类页的占位 feed：保留分类条/排序所需的 categories，网格清空。
  HomeFeed? _shellFor(FeedKey key) {
    final base = _chrome;
    if (base == null) return null;
    return base.copyWith(
      grid: const <JmAlbumSummary>[],
      gridPage: 1,
      gridTotal: 0,
      gridTotalCapped: false,
      gridExhausted: false,
      fromCache: false,
      updatedAt: DateTime.now(),
      partialErrors: const <String>[],
    );
  }

  /// 真正打网络：成功覆盖缓存；失败保留已有缓存（只有首次加载才进错误态）。
  Future<void> _load(FeedKey key) async {
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      final slug = _slugFor(key);
      final HomeFeed feed;
      if (_isDefault(key)) {
        feed = await repository.fetchFeed(
          order: key.order,
          persistCache: true,
        );
        _chrome = feed;
      } else {
        final page = await repository.categoryPage(
          categorySlug: slug,
          order: key.order,
        );
        final base = _chrome;
        if (base == null) {
          // 没有整页 chrome（极端情况）：退回四端点聚合，保证分类页也能渲染。
          feed = await repository.fetchFeed(
            categorySlug: slug,
            order: key.order,
            persistCache: false,
          );
          _chrome = feed;
        } else {
          feed = base.copyWith(
            grid: page.content,
            gridPage: 1,
            gridTotal: page.total,
            gridTotalCapped: page.total >= AppConfig.maxServerTotal,
            gridExhausted: false,
            fromCache: false,
            updatedAt: DateTime.now(),
            partialErrors: const <String>[],
          );
        }
      }
      if (_disposed || _current != key) return;
      _remember(key, feed);
      state = AsyncValue<HomeFeed>.data(feed);
      if (_isDefault(key)) unawaited(_prewarm(key, feed));
    } catch (error, stackTrace) {
      if (_disposed || _current != key) return;
      final cached = _feeds[key];
      if (cached != null && cached.grid.isNotEmpty) {
        state = AsyncValue<HomeFeed>.data(
          cached.copyWith(partialErrors: const <String>['刷新失败，先看上次内容']),
        );
        return;
      }
      // 分类页失败时别把整页打成错误态（分类条会一起消失）：
      // 保留外壳 + 底部重试条，用户还能换分类继续看。
      if (!_isDefault(key)) {
        final shell = _shellFor(key);
        if (shell != null) {
          ref.read(loadMoreErrorProvider.notifier).state =
              error is Exception ? error.toString() : '分类加载失败，请重试';
          state = AsyncValue<HomeFeed>.data(shell);
          return;
        }
      }
      state = AsyncValue<HomeFeed>.error(error, stackTrace);
    }
  }

  /// 预热：首屏出来后按 700ms 间隔偷偷拉几个分类的第一页（每个 1 次请求）。
  Future<void> _prewarm(FeedKey origin, HomeFeed feed) async {
    if (_prewarmed || _warming || feed.categories.isEmpty) return;
    final targets = feed.categories
        .where(
          (category) =>
              category.id.isNotEmpty &&
              !_isDefaultId(category.id) &&
              category.slug.isNotEmpty,
        )
        .take(AppConfig.homePrewarmCategories)
        .toList(growable: false);
    if (targets.isEmpty) return;

    _warming = true;
    _prewarmed = true;
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      for (final category in targets) {
        final key = (
          category: category.id,
          sub: '',
          order: origin.order,
        );
        if (_feeds.containsKey(key)) continue;
        await _sleep(AppConfig.homePrewarmSpacing);
        if (_disposed) return;
        final page = await repository.categoryPage(
          categorySlug: category.slug,
          order: origin.order,
        );
        if (page.content.isEmpty) continue;
        // 预热条目复用当前页的轮播 / 分节，只替换网格（省 3 次请求）。
        _feeds[key] = feed.copyWith(
          grid: page.content,
          gridPage: 1,
          gridTotal: page.total,
          gridTotalCapped: page.total >= AppConfig.maxServerTotal,
          gridExhausted: false,
          updatedAt: DateTime.now(),
          partialErrors: const <String>[],
        );
        _stamps[key] = DateTime.now();
        Log.i('分类预热 ${category.name}(${category.slug})：${page.content.length} 本');
      }
    } catch (error) {
      Log.w('分类预热失败：$error');
    } finally {
      _warming = false;
    }
  }

  static bool _isDefaultId(String id) => id.isEmpty || id == '0';

  /// 下拉刷新：回到第 1 页（真的打网络，不用缓存）。
  Future<void> refresh() async {
    final key = _current ??
        _keyOf(
          ref.read(selectedCategoryProvider),
          ref.read(albumOrderProvider),
        );
    ref.read(loadMoreErrorProvider.notifier).state = null;
    _feeds.remove(key);
    _stamps.remove(key);
    state = const AsyncValue<HomeFeed>.loading();
    // FutureProvider 会把失败缓存住：只有把仓储（以及失败的引导）作废，
    // 错误态的「重新加载」才可能真正重试，而不是重抛旧异常。
    ref.invalidate(homeRepositoryProvider);
    if (!ref.read(jmBootstrapProvider).hasValue) {
      ref.invalidate(jmBootstrapProvider);
    }
    await _load(key);
  }

  /// 底部「加载失败，点此重试」：网格还空着就重拉第一页，否则续翻下一页。
  Future<void> retry() async {
    final key = _current;
    if (key == null) return;
    ref.read(loadMoreErrorProvider.notifier).state = null;
    final current = state.valueOrNull;
    if (current == null || current.grid.isEmpty) {
      ref.read(loadingMoreProvider.notifier).state = true;
      try {
        await _load(key);
      } finally {
        if (!_disposed && _current == key) {
          ref.read(loadingMoreProvider.notifier).state = false;
        }
      }
      return;
    }
    await loadMore();
  }

  /// 触底加载下一页（到底后不再发请求）。
  Future<void> loadMore() async {
    if (ref.read(loadingMoreProvider)) return;
    final current = state.valueOrNull;
    if (current == null || current.gridExhausted) return;
    if (current.grid.isEmpty) return;
    final key = _current;
    if (key == null) return;

    ref.read(loadingMoreProvider.notifier).state = true;
    ref.read(loadMoreErrorProvider.notifier).state = null;
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      final next = await repository.loadMore(
        current,
        categorySlug: _slugFor(key),
        order: key.order,
        persistCache: _isDefault(key),
      );
      if (_disposed || _current != key) return;
      _remember(key, next);
      state = AsyncValue<HomeFeed>.data(next);
    } catch (error) {
      ref.read(loadMoreErrorProvider.notifier).state =
          error is Exception ? error.toString() : '加载失败，请重试';
    } finally {
      if (!_disposed) ref.read(loadingMoreProvider.notifier).state = false;
    }
  }

  /// 切换一级分类：清掉二级筛选，[build] 里的 `ref.listen` 会接管加载。
  void selectCategory(String categoryId) {
    final current = ref.read(selectedCategoryProvider);
    final next = (id: categoryId, sub: '');
    if (current == next) return;
    ref.read(selectedCategoryProvider.notifier).state = next;
  }

  /// 切换二级分类（父分类下的 漢化 / 日語 …）；[subSlug] 空串 = 全部。
  void selectSub(String subSlug) {
    final current = ref.read(selectedCategoryProvider);
    if (current.sub == subSlug) return;
    ref.read(selectedCategoryProvider.notifier).state =
        (id: current.id, sub: subSlug);
  }

  void selectOrder(AlbumOrder order) {
    if (ref.read(albumOrderProvider) == order) return;
    ref.read(albumOrderProvider.notifier).state = order;
  }
}
