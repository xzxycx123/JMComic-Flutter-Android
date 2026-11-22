import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/utils/logger.dart';
import '../../data/models/jm_album_meta.dart';
import '../../data/models/jm_album_summary.dart';
import 'widgets/album_card.dart';

/// 卡片元数据：**喜歡数 + 作品标签**，同一个 `/album?id=` 响应一次拿全。
///
/// 数据源只有一条：JmAPI `/album`。
///
/// 历史坑（0.4.2 首页点赞量显示不正确）：列表接口（`/promote`、`/latest`、
/// `/categories/filter`、`/search`）既不带计数也不带 `tags`，旧实现去抓官方网页
/// 列表，但网页给的是压缩写法（`21K` / `1.2万`），与详情页对不上。
///
/// 现在按卡片懒加载：每本只请求一次，成功后会话内缓存，顺手把 `tags`
/// （`泳裝 / 百合 / 扶他 …`）也缓存下来，给封面左上角的标签用。
class AlbumMetaState {
  const AlbumMetaState({
    this.likes = const <String, int>{},
    this.tags = const <String, List<String>>{},
    this.failed = const <String>{},
  });

  /// albumId -> likes（已确认过的精确值，含 0）。
  final Map<String, int> likes;

  /// albumId -> 作品标签（顺序按服务端，UI 侧再挑前两个展示）。
  final Map<String, List<String>> tags;

  /// 本次会话取数彻底失败（重试次数用尽）的 id：卡片保持 `--`，不再重试。
  final Set<String> failed;

  bool isResolved(String albumId) => likes.containsKey(albumId);

  List<String>? tagsOf(String albumId) => tags[albumId];

  AlbumMetaState copyWith({
    Map<String, int>? likes,
    Map<String, List<String>>? tags,
    Set<String>? failed,
  }) =>
      AlbumMetaState(
        likes: likes ?? this.likes,
        tags: tags ?? this.tags,
        failed: failed ?? this.failed,
      );
}

/// 单本元数据取数器（默认走 [AlbumRepository.meta]，即 JmAPI `/album`）。
///
/// 单测 / widget 测试 override 这个 Provider 即可，不打真实网络。
final Provider<Future<JmAlbumMeta> Function(String albumId)>
    albumMetaFetcherProvider =
    Provider<Future<JmAlbumMeta> Function(String albumId)>(
  (ref) => (String albumId) async {
    final repository = await ref.read(albumRepositoryProvider.future);
    return repository.meta(albumId);
  },
);

final NotifierProvider<AlbumMetaNotifier, AlbumMetaState> albumMetaProvider =
    NotifierProvider<AlbumMetaNotifier, AlbumMetaState>(
  AlbumMetaNotifier.new,
);

/// 把已解析的计数 / 标签并进卡片数据。
///
/// 计数只覆盖「已确认」的值：0 也算确认（真实 0 赞），
/// 但详情页已经给了更大的计数时不回退；标签只在拿到非空列表时覆盖。
JmAlbumSummary withResolvedMeta(
  JmAlbumSummary album, {
  int? likes,
  List<String>? tags,
}) {
  var result = album;
  if (likes != null) {
    final keepExisting = likes <= 0 && album.likes > 0;
    if (!keepExisting && likes != album.likes) {
      result = result.copyWith(likes: likes);
    }
  }
  if (tags != null && tags.isNotEmpty) {
    result = result.copyWith(tags: tags);
  }
  return result;
}

class AlbumMetaNotifier extends Notifier<AlbumMetaState> {
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
  AlbumMetaState build() {
    ref.onDispose(() {
      _disposed = true;
      _queue.clear();
      _queued.clear();
    });
    return const AlbumMetaState();
  }

  /// 请求一批卡片的元数据（幂等：已解析 / 排队中 / 在飞 / 已放弃都会跳过）。
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
    JmAlbumMeta? meta;
    try {
      final fetch = ref.read(albumMetaFetcherProvider);
      meta = await fetch(id);
    } catch (exception) {
      error = exception;
    } finally {
      _inflight.remove(id);
      _running--;
    }
    if (_disposed) return;

    if (meta != null) {
      _attempts.remove(id);
      final likes = meta.likes < 0 ? 0 : meta.likes;
      state = state.copyWith(
        likes: <String, int>{...state.likes, id: likes},
        tags: meta.tags.isEmpty
            ? state.tags
            : <String, List<String>>{...state.tags, id: meta.tags},
        failed: state.failed.isEmpty
            ? state.failed
            : (Set<String>.of(state.failed)..remove(id)),
      );
      Log.d('JmAPI 元数据 $id：likes=$likes tags=${meta.tags.length}');
    } else {
      final attempts = (_attempts[id] ?? 0) + 1;
      _attempts[id] = attempts;
      if (attempts >= maxAttempts) {
        state = state.copyWith(
          failed: <String>{...state.failed, id},
        );
        Log.d('JmAPI 元数据 $id 取数失败（已放弃）：$error');
      } else {
        Log.d('JmAPI 元数据 $id 取数失败（可重试）：$error');
      }
    }
    _drain();
  }
}

/// 带喜欢数 / 作品标签的卡片：自己负责「看到就补数」，并只在本卡数据变化时重建。
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
    final knownLikes = ref.watch(
      albumMetaProvider.select((state) => state.likes[album.id]),
    );
    final knownTags = ref.watch(
      albumMetaProvider.select((state) => state.tags[album.id]),
    );
    final failed = ref.watch(
      albumMetaProvider.select((state) => state.failed.contains(album.id)),
    );
    if (knownLikes == null && !failed) {
      ref.read(albumMetaProvider.notifier).ensure(<String>[album.id]);
    }
    final resolved = withResolvedMeta(
      album,
      likes: knownLikes,
      tags: knownTags,
    );
    return AlbumCard(
      album: resolved,
      layout: layout,
      caption: caption,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
