import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/local/progress_store.dart';
import '../../data/models/jm_album_detail.dart';

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

/// 本地收藏（v1 只存 id，不接登录接口）。
final NotifierProvider<FavoritesNotifier, Set<String>> favoritesProvider =
    NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

class FavoritesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => ref.watch(favoritesStoreProvider).read();

  bool contains(String albumId) => state.contains(albumId);

  Future<bool> toggle(String albumId) async {
    final added = await ref.read(favoritesStoreProvider).toggle(albumId);
    state = ref.read(favoritesStoreProvider).read();
    return added;
  }
}
