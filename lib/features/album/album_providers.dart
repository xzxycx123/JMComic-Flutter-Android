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
