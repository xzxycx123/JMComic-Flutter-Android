import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
import '../../core/utils/logger.dart';
import '../../data/local/hive_init.dart';
import '../../data/models/home_feed.dart';
import '../../data/repositories/home_repository.dart';

/// 当前选中的分类（chip）。
final StateProvider<String> selectedCategoryProvider = StateProvider<String>((ref) => '0');

/// 当前排序。
final StateProvider<AlbumOrder> albumOrderProvider =
    StateProvider<AlbumOrder>((ref) => AlbumOrder.latestUpdate);

/// 下一页加载失败的原因（UI 底部给"重试"条，不弹全屏错误）。
final StateProvider<String?> loadMoreErrorProvider = StateProvider<String?>((ref) => null);

/// 是否正在加载下一页。
final StateProvider<bool> loadingMoreProvider = StateProvider<bool>((ref) => false);

/// 标签页（分类 + 排序）组合键：首页内存缓存按它分桶。
typedef FeedKey = ({String category, AlbumOrder order});

final AsyncNotifierProvider<HomeFeedNotifier, HomeFeed> homeFeedProvider =
    AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

/// 首页 feed：**内存里按标签页缓存**，切回来先出缓存再后台刷新。
///
/// 之前 `build()` 里 `ref.watch(selectedCategoryProvider)` 会让每次点标签都整页重建
/// （清空网格、闪骨架屏、重新打 4 个接口），这里改成：
/// 1. [build] 只跑一次，用 `ref.listen` 监听标签页变化；
/// 2. 切到已缓存过的标签就立刻 `AsyncData(cached)`，超过 [AppConfig.categoryCacheTtl]
///    才在后台刷一页，不闪骨架屏、不清滚动位置；
/// 3. 首屏出来后空跑预热几个常用分类（每个只发 1 次 `/categories/filter`）。
class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  final Map<FeedKey, HomeFeed> _feeds = <FeedKey, HomeFeed>{};
  final Map<FeedKey, DateTime> _stamps = <FeedKey, DateTime>{};
  FeedKey? _current;
  bool _disposed = false;
  bool _prewarmed = false;
  bool _warming = false;
  Timer? _prewarmTimer;

  /// 首屏重试计数（下拉刷新 / 错误态重试都走 [refresh]）。
  @override
  Future<HomeFeed> build() async {
    ref.onDispose(() {
      _disposed = true;
      _prewarmTimer?.cancel();
    });

    ref.listen<String>(selectedCategoryProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_switchTo(next, ref.read(albumOrderProvider)));
    });
    ref.listen<AlbumOrder>(albumOrderProvider, (previous, next) {
      if (previous == next) return;
      unawaited(_switchTo(ref.read(selectedCategoryProvider), next));
    });

    final category = ref.read(selectedCategoryProvider);
    final order = ref.read(albumOrderProvider);
    final key = (category: category, order: order);
    _current = key;

    // 冷启动：先把「上次的主页」直接画出来（不看 TTL，也不等网络/引导），
    // 再后台拉新并在成功后整体替换（PLAN §6.2 的加强版）。
    if (_isDefault(key)) {
      final cached = HomeRepository.readCachedFeed(
        Hive.box<dynamic>(HiveBoxes.feedCache),
      );
      if (cached != null) {
        _remember(key, cached);
        unawaited(_load(key));
        return cached;
      }
    }

    final repository = await ref.watch(homeRepositoryProvider.future);
    final feed = await repository.fetchFeed(category: category, order: order);
    _remember(key, feed);
    unawaited(_prewarm(key, feed));
    return feed;
  }

  static bool _isDefault(FeedKey key) =>
      key.category == '0' && key.order == AlbumOrder.latestUpdate;

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
  Future<void> _switchTo(String category, AlbumOrder order) async {
    if (_disposed) return;
    final key = (category: category, order: order);
    if (_current == key) return;
    _current = key;
    ref.read(loadMoreErrorProvider.notifier).state = null;
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

    state = const AsyncValue<HomeFeed>.loading();
    await _load(key);
  }

  /// 真正打网络：成功覆盖缓存；失败保留已有缓存（只有首次加载才进错误态）。
  Future<void> _load(FeedKey key) async {
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      final feed = await repository.fetchFeed(
        category: key.category,
        order: key.order,
      );
      if (_disposed || _current != key) return;
      _remember(key, feed);
      state = AsyncValue<HomeFeed>.data(feed);
      unawaited(_prewarm(key, feed));
    } catch (error, stackTrace) {
      if (_disposed || _current != key) return;
      final cached = _feeds[key];
      if (cached != null && cached.grid.isNotEmpty) {
        state = AsyncValue<HomeFeed>.data(
          cached.copyWith(partialErrors: const <String>['刷新失败，先看上次内容']),
        );
        return;
      }
      state = AsyncValue<HomeFeed>.error(error, stackTrace);
    }
  }

  /// 预热：首屏出来后按 700ms 间隔偷偷拉几个分类的第一页（每个 1 次请求）。
  Future<void> _prewarm(FeedKey origin, HomeFeed feed) async {
    if (_prewarmed || _warming || feed.categories.isEmpty) return;
    final ids = feed.categories
        .map((category) => category.id)
        .where((id) => id.isNotEmpty && id != '0')
        .take(AppConfig.homePrewarmCategories)
        .toList(growable: false);
    if (ids.isEmpty) return;

    _warming = true;
    _prewarmed = true;
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      for (final id in ids) {
        final key = (category: id, order: origin.order);
        if (_feeds.containsKey(key)) continue;
        await _sleep(AppConfig.homePrewarmSpacing);
        if (_disposed) return;
        final page = await repository.categoryPage(
          category: id,
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
        );
        _stamps[key] = DateTime.now();
        Log.i('分类预热 $id：${page.content.length} 本');
      }
    } catch (error) {
      Log.w('分类预热失败：$error');
    } finally {
      _warming = false;
    }
  }

  /// 下拉刷新：回到第 1 页（真的打网络，不用缓存）。
  Future<void> refresh() async {
    final key = _current ??
        (category: ref.read(selectedCategoryProvider),
            order: ref.read(albumOrderProvider),);
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

  /// 触底加载下一页（到底后不再发请求）。
  Future<void> loadMore() async {
    if (ref.read(loadingMoreProvider)) return;
    final current = state.valueOrNull;
    if (current == null || current.gridExhausted) return;
    final key = _current;
    if (key == null) return;

    ref.read(loadingMoreProvider.notifier).state = true;
    ref.read(loadMoreErrorProvider.notifier).state = null;
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      final next = await repository.loadMore(
        current,
        category: key.category,
        order: key.order,
      );
      if (_disposed || _current != key) return;
      _remember(key, next);
      state = AsyncValue<HomeFeed>.data(next);
    } catch (error) {
      ref.read(loadMoreErrorProvider.notifier).state =
          error is Exception ? error.toString() : '加载失败，请重试';
    } finally {
      ref.read(loadingMoreProvider.notifier).state = false;
    }
  }

  /// 切换分类：只改选择状态，[build] 里的 `ref.listen` 会接管加载。
  void selectCategory(String categoryId) {
    if (ref.read(selectedCategoryProvider) == categoryId) return;
    ref.read(selectedCategoryProvider.notifier).state = categoryId;
  }

  void selectOrder(AlbumOrder order) {
    if (ref.read(albumOrderProvider) == order) return;
    ref.read(albumOrderProvider.notifier).state = order;
  }
}
