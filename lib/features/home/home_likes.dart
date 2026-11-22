import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/utils/logger.dart';
import '../../data/models/jm_album_summary.dart';
import 'widgets/album_card.dart';

/// 首页 / 搜索 / 收藏的「喜歡」数（点赞量）。
///
/// 数据源只有一条：**JmAPI `/album?id=` 的 `likes`**。
///
/// 历史坑（0.4.2 首页点赞量显示不正确）：列表接口（`/promote`、`/latest`、
/// `/categories/filter`、`/search`）不带计数，旧实现去抓官方网页列表
/// `<span id="albim_likes_1490702">21K</span>`，但网页给的是压缩写法
/// （`21K` / `1.2K` / `1.2万`），旧正则直取数字前缀，于是 21K 显示成 21、
/// 1.2K 显示成 1 —— 与详情页（走 `/album.likes`）对不上。
///
/// 现在改成按卡片懒加载走 JmAPI：每本只请求一次，成功后会话内缓存，
/// 与详情页同一个字段，天然一致。
class AlbumLikesState {
  const AlbumLikesState({
    this.likes = const <String, int>{},
    this.failed = const <String>{},
  });

  /// albumId -> likes（已确认过的精确值，含 0）。
  final Map<String, int> likes;

  /// 本次会话取数彻底失败（重试次数用尽）的 id：卡片保持 `--`，不再重试。
  final Set<String> failed;

  bool isResolved(String albumId) => likes.containsKey(albumId);

  AlbumLikesState copyWith({
    Map<String, int>? likes,
    Set<String>? failed,
  }) =>
      AlbumLikesState(
        likes: likes ?? this.likes,
        failed: failed ?? this.failed,
      );
}

/// 单本喜欢数取数器（默认走 [AlbumRepository.likes]，即 JmAPI `/album.likes`）。
///
/// 单测 / widget 测试 override 这个 Provider 即可，不打真实网络。
final Provider<Future<int> Function(String albumId)> albumLikesFetcherProvider =
    Provider<Future<int> Function(String albumId)>(
  (ref) => (String albumId) async {
    final repository = await ref.read(albumRepositoryProvider.future);
    return repository.likes(albumId);
  },
);

final NotifierProvider<AlbumLikesNotifier, AlbumLikesState> albumLikesProvider =
    NotifierProvider<AlbumLikesNotifier, AlbumLikesState>(
  AlbumLikesNotifier.new,
);

/// 把已解析的计数并进卡片数据。
///
/// 只覆盖「已确认」的值：0 也算确认（真实 0 赞），
/// 但详情页已经给了更大的计数时不回退。
JmAlbumSummary withResolvedLikes(
  JmAlbumSummary album,
  Map<String, int> likes,
) {
  final resolved = likes[album.id];
  if (resolved == null) return album;
  if (resolved == album.likes) return album;
  if (resolved <= 0 && album.likes > 0) return album;
  return album.copyWith(likes: resolved);
}

class AlbumLikesNotifier extends Notifier<AlbumLikesState> {
  /// 同时在飞的请求数：卡片一屏 6~10 张，4 路已经够快，
  /// 又不会一次性把整页 80 本全打到服务端。
  static const int maxConcurrent = 4;

  /// 单本最多尝试次数（成功后清零）；失败会等下次 build 再排一次队。
  static const int maxAttempts = 2;

  final Queue<String> _queue = Queue<String>();
  final Set<String> _queued = <String>{};
  final Set<String> _inflight = <String>{};
  final Map<String, int> _attempts = <String, int>{};
  int _running = 0;
  bool _disposed = false;

  @override
  AlbumLikesState build() {
    ref.onDispose(() {
      _disposed = true;
      _queue.clear();
      _queued.clear();
    });
    return const AlbumLikesState();
  }

  /// 请求一批卡片的喜欢数（幂等：已解析 / 排队中 / 在飞 / 已放弃都会跳过）。
  ///
  /// 在卡片 build 里调用即可：Sliver 只构建可视区附近，所以只会为真正
  /// 露出来的卡片补数，滚动时自然补齐。
  void ensure(Iterable<String> albumIds) {
    var added = false;
    for (final id in albumIds) {
      if (id.isEmpty) continue;
      if (state.likes.containsKey(id)) continue;
      if ((_attempts[id] ?? 0) >= maxAttempts) continue;
      if (_inflight.contains(id) || _queued.contains(id)) continue;
      _queue.add(id);
      _queued.add(id);
      added = true;
    }
    if (added) _drain();
  }

  void _drain() {
    while (!_disposed && _running < maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeFirst();
      _queued.remove(id);
      _inflight.add(id);
      _running++;
      // 微任务里起请求：ensure 常在 build 中被调用，避免同步改到 state。
      unawaited(Future<void>.microtask(() => _fetch(id)));
    }
  }

  Future<void> _fetch(String id) async {
    Object? error;
    int? likes;
    try {
      final fetch = ref.read(albumLikesFetcherProvider);
      likes = await fetch(id);
    } catch (exception) {
      error = exception;
    } finally {
      _inflight.remove(id);
      _running--;
    }
    if (_disposed) return;

    if (likes != null) {
      _attempts.remove(id);
      state = state.copyWith(
        likes: <String, int>{...state.likes, id: likes < 0 ? 0 : likes},
        failed: state.failed.isEmpty
            ? state.failed
            : (Set<String>.of(state.failed)..remove(id)),
      );
      Log.d('JmAPI 喜欢数 $id = $likes');
    } else {
      final attempts = (_attempts[id] ?? 0) + 1;
      _attempts[id] = attempts;
      if (attempts >= maxAttempts) {
        state = state.copyWith(
          failed: <String>{...state.failed, id},
        );
        Log.d('JmAPI 喜欢数 $id 取数失败（已放弃）：$error');
      } else {
        Log.d('JmAPI 喜欢数 $id 取数失败（可重试）：$error');
      }
    }
    _drain();
  }
}

/// 带喜欢数的卡片：自己负责「看到就补数」，并只在本卡计数变化时重建。
class LikesAlbumCard extends ConsumerWidget {
  const LikesAlbumCard({
    required this.album,
    super.key,
    this.layout = AlbumCardLayout.grid,
    this.caption,
    this.onTap,
    this.onLongPress,
  });

  final JmAlbumSummary album;
  final AlbumCardLayout layout;
  final Widget? caption;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = ref.watch(
      albumLikesProvider.select((state) => state.likes[album.id]),
    );
    final failed = ref.watch(
      albumLikesProvider.select((state) => state.failed.contains(album.id)),
    );
    if (known == null && !failed) {
      ref.read(albumLikesProvider.notifier).ensure(<String>[album.id]);
    }
    final resolved = known == null
        ? album
        : withResolvedLikes(album, <String, int>{album.id: known});
    return AlbumCard(
      album: resolved,
      layout: layout,
      caption: caption,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
