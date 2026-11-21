import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/di/providers.dart';
import '../../data/models/jm_album_summary.dart';
import '../../data/repositories/search_repository.dart';
import '../album/album_providers.dart';

final searchAlbumMetadataProvider =
    FutureProvider.autoDispose.family<SearchAlbumMetadata?, String>(
  (ref, albumId) async {
    final detailProvider = albumDetailProvider(albumId);
    if (ref.exists(detailProvider)) {
      final existing = ref.read(detailProvider);
      if (existing.hasValue) {
        return SearchAlbumMetadata.fromAlbum(existing.requireValue);
      }
      if (existing.isLoading) {
        try {
          final album = await ref.read(detailProvider.future);
          return SearchAlbumMetadata.fromAlbum(album);
        } on Exception {
          return null;
        }
      }
    }
    final repository = await ref.watch(searchRepositoryProvider.future);
    return repository.enrichAlbum(albumId);
  },
);

/// 搜索排序（服务端 `o` 参数，实测各值都会改变结果顺序）：
/// 时间 = `mr`、阅读数 = `mv`、人气 = `mp`、最新上架 = `md`。
const List<AlbumOrder> kSearchSorts = <AlbumOrder>[
  AlbumOrder.latestUpdate,
  AlbumOrder.mostViewed,
  AlbumOrder.popular,
  AlbumOrder.newest,
];

final StateProvider<AlbumOrder> searchSortProvider =
    StateProvider<AlbumOrder>((ref) => AlbumOrder.latestUpdate);

/// 搜索结果状态（首页 + 分页合并）。
class SearchResults {
  const SearchResults({
    required this.keyword,
    required this.items,
    required this.total,
    this.page = 1,
    this.loadingMore = false,
    this.order = AlbumOrder.latestUpdate,
    this.error,
  });

  final String keyword;
  final List<JmAlbumSummary> items;
  final int total;
  final int page;
  final bool loadingMore;

  /// 当前排序（切换排序会重新从第 1 页拉）。
  final AlbumOrder order;
  final String? error;

  bool get isEmpty => items.isEmpty;

  SearchResults copyWith({
    List<JmAlbumSummary>? items,
    int? total,
    int? page,
    bool? loadingMore,
    AlbumOrder? order,
    String? error,
    bool clearError = false,
  }) =>
      SearchResults(
        keyword: keyword,
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        loadingMore: loadingMore ?? this.loadingMore,
        order: order ?? this.order,
        error: clearError ? null : (error ?? this.error),
      );
}

final NotifierProvider<SearchHistoryNotifier, List<String>>
    searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
  SearchHistoryNotifier.new,
);

class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(searchHistoryStoreProvider).read();

  Future<void> push(String keyword) async {
    state = await ref.read(searchHistoryStoreProvider).push(keyword);
  }

  Future<void> remove(String keyword) async {
    final store = ref.read(searchHistoryStoreProvider);
    await store.remove(keyword);
    state = store.read();
  }

  Future<void> clear() async {
    await ref.read(searchHistoryStoreProvider).clear();
    state = const <String>[];
  }
}

final AsyncNotifierProvider<SearchController, SearchResults?>
    searchControllerProvider =
    AsyncNotifierProvider<SearchController, SearchResults?>(
  SearchController.new,
  dependencies: [searchSortProvider],
);

class SearchController extends AsyncNotifier<SearchResults?> {
  @override
  SearchResults? build() => null;

  Future<void> search(String keyword, {AlbumOrder? order}) async {
    final value = keyword.trim();
    if (value.isEmpty) {
      state = const AsyncValue<SearchResults?>.data(null);
      return;
    }
    final AlbumOrder sort = order ?? ref.read(searchSortProvider);
    state = const AsyncValue<SearchResults?>.loading();
    state = await AsyncValue.guard(() async {
      final repository = await ref.read(searchRepositoryProvider.future);
      await repository.remember(value);
      unawaited(ref.read(searchHistoryProvider.notifier).push(value));
      final page =
          await repository.search(keyword: value, page: 1, order: sort);
      return SearchResults(
        keyword: value,
        items: page.content,
        total: page.total,
        page: 1,
        order: sort,
      );
    });
  }

  /// 切换排序：有结果时立刻按新顺序重拉第 1 页。
  Future<void> setSort(AlbumOrder order) async {
    if (ref.read(searchSortProvider) == order) return;
    ref.read(searchSortProvider.notifier).state = order;
    final current = state.valueOrNull;
    if (current == null) return;
    await search(current.keyword, order: order);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore) return;
    if (current.items.length >= current.total) return;

    state = AsyncValue<SearchResults?>.data(
      current.copyWith(loadingMore: true, clearError: true),
    );
    try {
      final repository = await ref.read(searchRepositoryProvider.future);
      final next = await repository.search(
        keyword: current.keyword,
        page: current.page + 1,
        order: current.order,
      );
      final merged = <JmAlbumSummary>[...current.items];
      final seen = merged.map((item) => item.id).toSet();
      for (final item in next.content) {
        if (seen.add(item.id)) merged.add(item);
      }
      state = AsyncValue<SearchResults?>.data(
        current.copyWith(
          items: merged,
          total: next.total > 0 ? next.total : current.total,
          page: current.page + 1,
          loadingMore: false,
          clearError: true,
        ),
      );
    } catch (error) {
      state = AsyncValue<SearchResults?>.data(
        current.copyWith(loadingMore: false, error: '$error'),
      );
    }
  }

  void reset() => state = const AsyncValue<SearchResults?>.data(null);
}

/// 搜索输入判定（纯本地，先判再发请求）。
SearchQuery resolveQuery(String input, {bool forceKeyword = false}) =>
    resolveSearchQuery(input, forceKeyword: forceKeyword);

/// 热门词（v1 用固定文案，点击直接搜索）。
const List<String> kHotKeywords = <String>[
  '同人',
  '單本',
  '韓漫',
  'C108',
  '中文',
  '全彩',
];
