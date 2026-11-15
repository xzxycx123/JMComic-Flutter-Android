import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
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

final AsyncNotifierProvider<HomeFeedNotifier, HomeFeed> homeFeedProvider =
    AsyncNotifierProvider<HomeFeedNotifier, HomeFeed>(HomeFeedNotifier.new);

class HomeFeedNotifier extends AsyncNotifier<HomeFeed> {
  @override
  Future<HomeFeed> build() async {
    final category = ref.watch(selectedCategoryProvider);
    final order = ref.watch(albumOrderProvider);
    final repository = await ref.watch(homeRepositoryProvider.future);

    final cached = repository.readCache();
    final useCache =
        cached != null && !repository.cacheExpired() && category == '0' && order == AlbumOrder.latestUpdate;
    if (useCache) {
      // 先渲染缓存，再后台刷新（PLAN §6.2）。
      unawaited(_refreshInBackground(repository, category, order));
      return cached;
    }
    return repository.fetchFeed(category: category, order: order);
  }

  Future<void> _refreshInBackground(
    HomeRepository repository,
    String category,
    AlbumOrder order,
  ) async {
    try {
      final fresh = await repository.fetchFeed(category: category, order: order);
      state = AsyncValue<HomeFeed>.data(fresh);
    } catch (_) {
      // 后台刷新失败保持缓存内容，不打断用户。
    }
  }

  /// 下拉刷新：回到第 1 页。
  Future<void> refresh() async {
    final category = ref.read(selectedCategoryProvider);
    final order = ref.read(albumOrderProvider);
    ref.read(loadMoreErrorProvider.notifier).state = null;
    state = const AsyncValue<HomeFeed>.loading();
    state = await AsyncValue.guard(() async {
      // FutureProvider 会把失败缓存住：只有把仓储（以及失败的引导）作废，
      // 错误态的「重新加载」才可能真正重试，而不是重抛旧异常。
      ref.invalidate(homeRepositoryProvider);
      if (!ref.read(jmBootstrapProvider).hasValue) {
        ref.invalidate(jmBootstrapProvider);
      }
      final repository = await ref.read(homeRepositoryProvider.future);
      return repository.fetchFeed(category: category, order: order);
    });
  }

  /// 触底加载下一页（到底后不再发请求）。
  Future<void> loadMore() async {
    if (ref.read(loadingMoreProvider)) return;
    final current = state.valueOrNull;
    if (current == null || current.gridExhausted) return;

    ref.read(loadingMoreProvider.notifier).state = true;
    ref.read(loadMoreErrorProvider.notifier).state = null;
    try {
      final repository = await ref.read(homeRepositoryProvider.future);
      final next = await repository.loadMore(
        current,
        category: ref.read(selectedCategoryProvider),
        order: ref.read(albumOrderProvider),
      );
      state = AsyncValue<HomeFeed>.data(next);
    } catch (error) {
      ref.read(loadMoreErrorProvider.notifier).state =
          error is Exception ? error.toString() : '加载失败，请重试';
    } finally {
      ref.read(loadingMoreProvider.notifier).state = false;
    }
  }

  /// 切换分类：重置分页（provider 依赖变化自动重建）。
  void selectCategory(String categoryId) {
    if (ref.read(selectedCategoryProvider) == categoryId) return;
    ref.read(selectedCategoryProvider.notifier).state = categoryId;
  }

  void selectOrder(AlbumOrder order) {
    if (ref.read(albumOrderProvider) == order) return;
    ref.read(albumOrderProvider.notifier).state = order;
  }
}
