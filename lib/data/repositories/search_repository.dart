import 'dart:async';
import 'dart:collection';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/jm_id_parser.dart';
import '../local/progress_store.dart';
import '../models/jm_album_detail.dart';
import '../models/jm_search_page.dart';
import '../sources/jm_api_client.dart';

/// 搜索输入的本地判定结果（PLAN §7.4）。
enum SearchQueryKind {
  /// 空输入：显示历史 + 热门词，不发请求。
  empty,

  /// 识别为车号：直接进详情页。
  album,

  /// 关键词：走 GET /search。
  keyword,
}

class SearchQuery {
  const SearchQuery({
    required this.kind,
    this.raw = '',
    this.albumId,
    this.keyword,
  });

  final SearchQueryKind kind;
  final String raw;
  final String? albumId;
  final String? keyword;

  bool get isEmpty => kind == SearchQueryKind.empty;
  bool get isAlbum => kind == SearchQueryKind.album;
  bool get isKeyword => kind == SearchQueryKind.keyword;

  /// 搜索框下方的实时提示文案。
  String get hint => switch (kind) {
        SearchQueryKind.empty => '输入车号或关键词',
        SearchQueryKind.album => '识别为车号 JM$albumId · 回车直达详情',
        SearchQueryKind.keyword => '关键词 · 回车搜索',
      };
}

/// 纯本地判定：先判再发请求（双保险交给服务端 redirect_aid）。
SearchQuery resolveSearchQuery(String input, {bool forceKeyword = false}) {
  final value = input.trim();
  if (value.isEmpty) return const SearchQuery(kind: SearchQueryKind.empty);
  final albumId = forceKeyword ? null : parseJmId(value);
  if (albumId != null) {
    return SearchQuery(
      kind: SearchQueryKind.album,
      raw: value,
      albumId: albumId,
    );
  }
  return SearchQuery(
    kind: SearchQueryKind.keyword,
    raw: value,
    keyword: value,
  );
}

class SearchAlbumMetadata {
  const SearchAlbumMetadata({required this.author, required this.tags});

  factory SearchAlbumMetadata.fromAlbum(JmAlbumDetail album) =>
      SearchAlbumMetadata(
        author: album.author,
        tags: album.tags,
      );

  final String author;
  final List<String> tags;
}

class SearchRepository {
  SearchRepository({
    required JmApi api,
    required SearchHistoryStore history,
  })  : _api = api,
        _history = history;

  final JmApi _api;
  final SearchHistoryStore _history;

  static const _metadataCacheLimit = 64;
  static const _metadataQueueLimit = 16;
  static const _metadataConcurrency = 2;
  final _metadataCache = <String, SearchAlbumMetadata?>{};
  final _metadataPending = <String, Completer<SearchAlbumMetadata?>>{};
  final _metadataQueue = Queue<String>();
  int _activeMetadata = 0;

  /// Fetches optional card metadata without delaying the search response.
  Future<SearchAlbumMetadata?> enrichAlbum(String albumId) {
    if (_metadataCache.containsKey(albumId)) {
      final cached = _metadataCache.remove(albumId);
      _metadataCache[albumId] = cached;
      return Future.value(cached);
    }
    final pending = _metadataPending[albumId];
    if (pending != null) return pending.future;
    if (_metadataQueue.length >= _metadataQueueLimit) return Future.value();

    final request = Completer<SearchAlbumMetadata?>();
    _metadataPending[albumId] = request;
    _metadataQueue.addLast(albumId);
    _drainMetadata();
    return request.future;
  }

  void _drainMetadata() {
    while (
        _activeMetadata < _metadataConcurrency && _metadataQueue.isNotEmpty) {
      final albumId = _metadataQueue.removeFirst();
      _activeMetadata++;
      unawaited(_fetchMetadata(albumId));
    }
  }

  Future<void> _fetchMetadata(String albumId) async {
    SearchAlbumMetadata? metadata;
    try {
      metadata = SearchAlbumMetadata.fromAlbum(await _api.getAlbum(albumId));
    } on Exception {
      // Optional enrichment must never turn a successful search into an error.
    } finally {
      _metadataCache[albumId] = metadata;
      if (_metadataCache.length > _metadataCacheLimit) {
        _metadataCache.remove(_metadataCache.keys.first);
      }
      _metadataPending.remove(albumId)?.complete(metadata);
      _activeMetadata--;
      _drainMetadata();
    }
  }

  List<String> get history => _history.read();

  Future<List<String>> remember(String keyword) => _history.push(keyword);

  Future<void> clearHistory() => _history.clear();

  Future<JmSearchPage> search({
    required String keyword,
    int page = 1,
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) =>
      _api.search(query: keyword, page: page, order: order);

  /// 服务端命中车号时返回 redirect_aid（关键词形态的双保险）。
  Future<String?> resolveRedirect(String keyword) async {
    final id = parseJmId(keyword);
    if (id != null) return id;
    try {
      final page = await _api.search(query: keyword, page: 1);
      return page.redirectAid;
    } catch (_) {
      return null;
    }
  }
}
