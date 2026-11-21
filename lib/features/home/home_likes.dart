import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/logger.dart';
import '../../data/models/jm_album_summary.dart';
import '../../data/sources/jm_likes_scraper.dart';

/// 喜欢数快照：按 id 缓存 + 记录命中的官方网页线路。
class AlbumLikesState {
  const AlbumLikesState({
    this.likes = const <String, int>{},
    this.host = '',
    this.domestic = false,
  });

  final Map<String, int> likes;

  /// 命中过的网页域名。
  final String host;

  /// 命中的是「国内」线路（comic18j-*）还是「国外」线路（18comic.* / jmcomic-*）。
  final bool domestic;

  bool get hasHost => host.isNotEmpty;

  AlbumLikesState copyWith({
    Map<String, int>? likes,
    String? host,
    bool? domestic,
  }) =>
      AlbumLikesState(
        likes: likes ?? this.likes,
        host: host ?? this.host,
        domestic: domestic ?? this.domestic,
      );
}

/// 网页 HTML 抓取器（默认走 [JmLikesScraper]；测试里 override 成假数据）。
final Provider<Future<String?> Function(Uri)> albumLikesHtmlProvider =
    Provider<Future<String?> Function(Uri)>(
  (ref) => (Uri uri) => const JmLikesScraper().fetch(uri),
);

/// 喜欢数缓存（id -> likes）。
final NotifierProvider<AlbumLikesNotifier, AlbumLikesState> albumLikesProvider =
    NotifierProvider<AlbumLikesNotifier, AlbumLikesState>(
  AlbumLikesNotifier.new,
);

/// 把抓到的喜欢数并进卡片数据（0 / 缺失保持原样，卡片显示 `--`）。
JmAlbumSummary withScrapedLikes(
  JmAlbumSummary album,
  Map<String, int> likes,
) {
  final resolved = likes[album.id];
  if (resolved == null || resolved <= 0 || resolved == album.likes) {
    return album;
  }
  return album.copyWith(likes: resolved);
}

class AlbumLikesNotifier extends Notifier<AlbumLikesState> {
  /// 已抓过的 `kind#参数#页码`，避免每次 rebuild 都打网络。
  final Set<String> _done = <String>{};

  /// 本次会话里确认不通的线路，后续翻页不再重试（避免每次白跑 7 条线路）。
  final Set<String> _deadHosts = <String>{};
  bool _busy = false;

  @override
  AlbumLikesState build() => const AlbumLikesState();

  /// 官方网页线路：国内（comic18j-*）优先，其次国外（18comic.* / jmcomic-*）。
  ///
  /// 两边是不同区域站点，同一本子的计数一致；哪个能通就用哪个，并把
  /// `domestic` 记进 state（日志里能看出走的是国内还是国外线路）。
  static List<({String host, bool domestic})> get webCandidates =>
      <({String host, bool domestic})>[
        for (final host in JmConstants.domesticHosts)
          (host: host, domestic: true),
        for (final host in JmConstants.overseasWebHosts)
          (host: host, domestic: false),
      ];

  /// 首页 / 分类 / 排序 feed：按页抓 `/albums?page=N&o=<排序>`。
  void ensurePage({
    required int page,
    required String order,
    String category = '0',
  }) {
    final safePage = page < 1 ? 1 : page;
    final safeOrder = order.isEmpty ? 'mr' : order;
    final key = 'list#$safeOrder#$category#$safePage';
    if (!_done.add(key)) return;
    unawaited(
      _load(
        page: safePage,
        key: key,
        buildUri: (host) => JmLikesScraper.listUri(
          host,
          page: safePage,
          order: safeOrder,
          category: category,
        ),
      ),
    );
  }

  /// 搜索结果页：抓 `/search/photos?search_query=<q>&page=N`。
  void ensureSearch({
    required String query,
    required int page,
    String order = '',
  }) {
    final value = query.trim();
    if (value.isEmpty) return;
    final safePage = page < 1 ? 1 : page;
    final key = 'search#$value#$order#$safePage';
    if (!_done.add(key)) return;
    unawaited(
      _load(
        page: safePage,
        key: key,
        buildUri: (host) => JmLikesScraper.searchUri(
          host,
          query: value,
          page: safePage,
          order: order,
        ),
      ),
    );
  }

  Future<void> _load({
    required int page,
    required String key,
    required Uri Function(String host) buildUri,
  }) async {
    if (_busy) return;
    _busy = true;
    try {
      final fetch = ref.read(albumLikesHtmlProvider);
      final cachedHost = state.host;
      // 先用上次成功过的线路；没缓存就从国内第一条开始，国内不通再国外。
      final candidates = <({String host, bool domestic})>[
        if (cachedHost.isNotEmpty && !_deadHosts.contains(cachedHost))
          (host: cachedHost, domestic: state.domestic),
        ...webCandidates.where(
          (candidate) =>
              candidate.host != cachedHost &&
              !_deadHosts.contains(candidate.host),
        ),
      ];
      for (final candidate in candidates) {
        final html = await fetch(buildUri(candidate.host));
        if (html == null) {
          _deadHosts.add(candidate.host);
          continue;
        }
        final parsed = JmLikesScraper.parse(html);
        if (parsed.isEmpty) {
          _deadHosts.add(candidate.host);
          continue;
        }
        state = state.copyWith(
          likes: <String, int>{...state.likes, ...parsed},
          host: candidate.host,
          domestic: candidate.domestic,
        );
        Log.i(
          '喜欢数补全 ${parsed.length} 本（${candidate.host} · '
          '${candidate.domestic ? '国内线路' : '国外线路'}）',
        );
        return;
      }
      // 全挂：允许下次重试这一页。
      _done.remove(key);
      Log.d('喜欢数补全：本页所有网页线路都没拿到计数（page=$page）');
    } finally {
      _busy = false;
    }
  }
}
