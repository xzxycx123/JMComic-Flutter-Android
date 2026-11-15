import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/network/api_exception.dart';
import '../../data/local/progress_store.dart';
import '../../data/models/jm_album_detail.dart';
import '../../data/models/jm_comment.dart';
import '../collect/collect_providers.dart';

/// 专辑详情（按 albumId 缓存，切走再回不重复请求）。
final FutureProviderFamily<JmAlbumDetail, String> albumDetailProvider =
    FutureProvider.family<JmAlbumDetail, String>((ref, albumId) async {
  final repository = await ref.watch(albumRepositoryProvider.future);
  return repository.album(albumId);
});

/// 章节阅读进度（详情页「继续阅读 · 第 12 页」）。
final ProviderFamily<ReaderProgress?, ({String albumId, String chapterId})>
    chapterProgressProvider =
    Provider.family<ReaderProgress?, ({String albumId, String chapterId})>(
  (ref, args) => ref.watch(progressStoreProvider).read(args.albumId, args.chapterId),
);

// ---------------------------------------------------------------- 点赞
/// 点赞状态：`liked` 取服务端 `/album.liked`，`likes` 是「喜歡」数。
class AlbumLikeState {
  const AlbumLikeState({
    this.liked = false,
    this.likes = 0,
    this.error,
  });

  final bool liked;
  final int likes;
  final String? error;

  AlbumLikeState copyWith({
    bool? liked,
    int? likes,
    String? error,
    bool clearError = false,
  }) =>
      AlbumLikeState(
        liked: liked ?? this.liked,
        likes: likes ?? this.likes,
        error: clearError ? null : (error ?? this.error),
      );
}

final NotifierProviderFamily<AlbumLikeNotifier, AlbumLikeState, String>
    albumLikeProvider =
    NotifierProvider.family<AlbumLikeNotifier, AlbumLikeState, String>(
  AlbumLikeNotifier.new,
);

/// 点赞：**先亮成功、后台发送**（服务端 `/like` 不回计数，失败再回滚）。
///
/// 不 `watch` 详情：否则详情一刷新就把刚点上的赞覆盖回旧值。
class AlbumLikeNotifier extends FamilyNotifier<AlbumLikeState, String> {
  bool _inFlight = false;

  @override
  AlbumLikeState build(String albumId) {
    final detail = ref.read(albumDetailProvider(albumId)).valueOrNull;
    return AlbumLikeState(
      liked: detail?.liked ?? false,
      likes: detail?.likes ?? 0,
    );
  }

  /// 返回 false 表示后台发送失败（状态已自动回滚）。
  Future<bool> like() async {
    if (state.liked || _inFlight) return false;
    _inFlight = true;
    final before = state;
    // 前台立刻成功：不转圈、不等网络。
    state = AlbumLikeState(liked: true, likes: before.likes + 1);
    try {
      final repository = await ref.read(albumRepositoryProvider.future);
      await repository.like(arg);
      return true;
    } catch (error) {
      state = before.copyWith(error: '$error');
      return false;
    } finally {
      _inFlight = false;
    }
  }

  void clearError() => state = state.copyWith(clearError: true);
}

// ---------------------------------------------------------------- 评论
/// 评论列表状态（分页 + 发送）。
class AlbumCommentsState {
  const AlbumCommentsState({
    this.items = const <JmComment>[],
    this.total = 0,
    this.page = 1,
    this.hasMore = false,
    this.loadingMore = false,
    this.loading = false,
    this.error,
  });

  final List<JmComment> items;
  final int total;
  final int page;
  final bool hasMore;
  final bool loadingMore;
  final bool loading;
  final String? error;

  bool get isEmpty => items.isEmpty;

  /// 评论区默认只铺最近几条，点「查看全部」再展开。
  List<JmComment> get preview => items.take(5).toList(growable: false);

  AlbumCommentsState copyWith({
    List<JmComment>? items,
    int? total,
    int? page,
    bool? hasMore,
    bool? loadingMore,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      AlbumCommentsState(
        items: items ?? this.items,
        total: total ?? this.total,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

final AsyncNotifierProviderFamily<AlbumCommentsNotifier, AlbumCommentsState,
    String> albumCommentsProvider =
    AsyncNotifierProvider.family<AlbumCommentsNotifier, AlbumCommentsState, String>(
  AlbumCommentsNotifier.new,
);

class AlbumCommentsNotifier
    extends FamilyAsyncNotifier<AlbumCommentsState, String> {
  static const int pageSize = 20;

  @override
  Future<AlbumCommentsState> build(String albumId) async {
    final repository = await ref.watch(albumRepositoryProvider.future);
    final page = await repository.comments(albumId, page: 1);
    return AlbumCommentsState(
      items: page.items,
      total: page.total,
      page: 1,
      hasMore: page.hasMore(pageSize: pageSize),
    );
  }

  /// 下拉/重试：回到第 1 页。
  Future<void> refresh() async {
    final current = state.valueOrNull;
    state = AsyncValue<AlbumCommentsState>.data(
      (current ?? const AlbumCommentsState()).copyWith(loading: true, clearError: true),
    );
    try {
      final repository = await ref.read(albumRepositoryProvider.future);
      final page = await repository.comments(arg, page: 1);
      state = AsyncValue<AlbumCommentsState>.data(
        AlbumCommentsState(
          items: page.items,
          total: page.total,
          page: 1,
          hasMore: page.hasMore(pageSize: pageSize),
        ),
      );
    } catch (error) {
      state = AsyncValue<AlbumCommentsState>.data(
        (current ?? const AlbumCommentsState())
            .copyWith(loading: false, error: '$error'),
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncValue<AlbumCommentsState>.data(
      current.copyWith(loadingMore: true, clearError: true),
    );
    try {
      final repository = await ref.read(albumRepositoryProvider.future);
      final next = await repository.comments(arg, page: current.page + 1);
      final seen = <String>{};
      final merged = <JmComment>[
        for (final item in <JmComment>[...current.items, ...next.items])
          if (item.id.isEmpty || seen.add(item.id)) item,
      ];
      state = AsyncValue<AlbumCommentsState>.data(
        current.copyWith(
          items: merged,
          total: next.total > 0 ? next.total : current.total,
          page: next.page,
          hasMore: next.hasMore(pageSize: pageSize),
          loadingMore: false,
        ),
      );
    } catch (error) {
      state = AsyncValue<AlbumCommentsState>.data(
        current.copyWith(loadingMore: false, error: '$error'),
      );
    }
  }

  /// 发评论：**先把评论插到列表顶部（发送中），再后台提交**。
  ///
  /// 成功：把 `pending` 摘掉（正文保留，不清空用户的评论）；
  /// 失败：撤掉这条并抛出原因，由调用方提示。
  Future<String> post(
    String content, {
    bool spoiler = false,
    String? parentId,
  }) async {
    final text = content.trim();
    if (text.isEmpty) throw const JmContentException('评论内容不能为空');

    final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    final before = state.valueOrNull ?? const AlbumCommentsState();
    final author = ref.read(accountSessionProvider).valueOrNull?.username ?? '';
    final optimistic = JmComment(
      id: pendingId,
      albumId: arg,
      username: author,
      nickname: author,
      content: text,
      spoiler: spoiler,
      parentId: parentId ?? '0',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      pending: true,
    );
    state = AsyncValue<AlbumCommentsState>.data(
      before.copyWith(
        items: <JmComment>[optimistic, ...before.items],
        total: before.total + 1,
        clearError: true,
      ),
    );

    try {
      final repository = await ref.read(albumRepositoryProvider.future);
      final message = await repository.postComment(
        albumId: arg,
        content: text,
        spoiler: spoiler,
        parentId: parentId,
      );
      // 成功后只摘掉「发送中」标记，不用整页刷新（避免服务端还没收录时评论凭空消失）。
      final current = state.valueOrNull ?? before;
      state = AsyncValue<AlbumCommentsState>.data(
        current.copyWith(
          items: current.items
              .map((item) =>
                  item.id == pendingId ? item.copyWith(pending: false) : item,)
              .toList(growable: false),
        ),
      );
      return message;
    } catch (error) {
      final current = state.valueOrNull ?? before;
      state = AsyncValue<AlbumCommentsState>.data(
        current.copyWith(
          items: current.items
              .where((item) => item.id != pendingId)
              .toList(growable: false),
          total: current.total > 0 ? current.total - 1 : 0,
          error: '$error',
        ),
      );
      rethrow;
    }
  }
}
