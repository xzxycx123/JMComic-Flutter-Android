import 'package:hive_ce/hive.dart';

import '../models/favorite_item.dart';
import '../models/jm_album_summary.dart';

/// 收藏本地账本：per-album 记录 + 本地文件夹 + outbox。
///
/// 读取永远走本地；网络只在对账时参与（见 `FavoritesRepository`）。
class FavoritesStore {
  FavoritesStore({
    required Box<dynamic> favorites,
    required Box<dynamic> folders,
    required Box<dynamic> outbox,
  })  : _favorites = favorites,
        _folders = folders,
        _outbox = outbox;

  static const String _legacyIdsKey = 'ids';
  static const String _outboxSeqKey = 'seq';

  final Box<dynamic> _favorites;
  final Box<dynamic> _folders;
  final Box<dynamic> _outbox;

  // ---------------------------------------------------------------- 迁移
  /// 老格式 `jm_favorites = {ids:[...]}` -> per-album 记录；重复执行安全。
  Future<void> migrateIfNeeded() async {
    final legacy = _favorites.get(_legacyIdsKey);
    if (legacy is List) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final value in legacy) {
        final albumId = '$value';
        if (albumId.isEmpty || _favorites.containsKey(albumId)) continue;
        await _favorites.put(
          albumId,
          FavoriteItem(albumId: albumId, addedAt: now).toJson(),
        );
      }
      await _favorites.delete(_legacyIdsKey);
    }
    if (!_folders.containsKey(FavoriteFolder.defaultFolder.id)) {
      await _folders.put(
        FavoriteFolder.defaultFolder.id,
        FavoriteFolder.defaultFolder.toJson(),
      );
    }
  }

  // ---------------------------------------------------------------- 条目
  List<FavoriteItem> get items {
    final result = <FavoriteItem>[];
    for (final key in _favorites.keys) {
      if (key == _legacyIdsKey) continue;
      final raw = _favorites.get(key);
      if (raw is! Map) continue;
      final item = FavoriteItem.fromJson(
        raw.map((mapKey, value) => MapEntry('$mapKey', value)),
      );
      if (item.albumId.isEmpty) continue;
      result.add(item);
    }
    result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return result;
  }

  FavoriteItem? item(String albumId) {
    final raw = _favorites.get(albumId);
    if (raw is! Map) return null;
    return FavoriteItem.fromJson(
      raw.map((key, value) => MapEntry('$key', value)),
    );
  }

  bool contains(String albumId) => _favorites.containsKey(albumId);

  int get count => items.length;

  Future<FavoriteItem> addFromSummary(
    JmAlbumSummary album, {
    String folderId = 'default',
    FavoriteSyncState sync = FavoriteSyncState.localOnly,
  }) async {
    final existing = item(album.id);
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = (existing ?? FavoriteItem(albumId: album.id, addedAt: now)).copyWith(
      title: album.title,
      // 本地账本里的作者也存规范名（去掉 `[作者]` 的中括号）。
      author: album.authorName,
      categoryId: album.categoryId,
      categoryTitle: album.categoryTitle,
      updateAt: album.updateAt,
      sync: sync,
    );
    final folders = <String>{folderId, 'default', ...next.folderIds}.toList(growable: false);
    await put(next.copyWith(folderIds: folders));
    return item(album.id)!;
  }

  Future<void> put(FavoriteItem item) => _favorites.put(item.albumId, item.toJson());

  Future<void> remove(String albumId) => _favorites.delete(albumId);

  Future<void> setSync(String albumId, FavoriteSyncState state, {String? error}) async {
    final current = item(albumId);
    if (current == null) return;
    await put(
      current.copyWith(
        sync: state,
        lastError: error,
        clearError: error == null,
      ),
    );
  }

  Future<void> setLastSeen(String albumId, int timestamp) async {
    final current = item(albumId);
    if (current == null) return;
    await put(current.copyWith(lastSeenAt: timestamp));
  }

  /// 登出后：已同步记录降级成「仅本地」，避免推到下一个账号。
  Future<void> demoteSyncedToLocal() async {
    for (final item in items) {
      if (item.sync == FavoriteSyncState.synced ||
          item.sync == FavoriteSyncState.pendingAdd) {
        await put(item.copyWith(sync: FavoriteSyncState.localOnly));
      }
    }
  }

  Future<void> clearAll() async {
    await _favorites.clear();
    await _outbox.clear();
  }

  // ---------------------------------------------------------------- 文件夹
  List<FavoriteFolder> get folders {
    final result = <FavoriteFolder>[];
    for (final key in _folders.keys) {
      final raw = _folders.get(key);
      if (raw is! Map) continue;
      result.add(
        FavoriteFolder.fromJson(raw.map((mapKey, value) => MapEntry('$mapKey', value))),
      );
    }
    result.sort((a, b) => a.order.compareTo(b.order));
    if (result.every((folder) => folder.id != 'default')) {
      result.insert(0, FavoriteFolder.defaultFolder);
    }
    return result;
  }

  Future<FavoriteFolder> createFolder(String name) async {
    final trimmed = name.trim();
    final id = 'f-${DateTime.now().millisecondsSinceEpoch}';
    final folder = FavoriteFolder(
      id: id,
      name: trimmed.isEmpty ? '新文件夹' : trimmed,
      order: folders.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _folders.put(id, folder.toJson());
    return folder;
  }

  Future<void> deleteFolder(String folderId) async {
    if (folderId == 'default') return;
    await _folders.delete(folderId);
    for (final item in items) {
      if (!item.folderIds.contains(folderId)) continue;
      await put(
        item.copyWith(
          folderIds: item.folderIds.where((id) => id != folderId).toSet().toList(),
        ),
      );
    }
  }

  Future<void> assignFolder(String albumId, String folderId) async {
    final current = item(albumId);
    if (current == null) return;
    final next = <String>{...current.folderIds, folderId, 'default'}.toList(growable: false);
    await put(current.copyWith(folderIds: next));
  }

  Future<void> removeFromFolder(String albumId, String folderId) async {
    if (folderId == 'default') return;
    final current = item(albumId);
    if (current == null) return;
    final next = current.folderIds.where((id) => id != folderId).toList(growable: false);
    await put(current.copyWith(folderIds: <String>{...next, 'default'}.toList()));
  }

  // ---------------------------------------------------------------- outbox
  List<FavoriteOutboxEntry> get outbox {
    final result = <FavoriteOutboxEntry>[];
    for (final key in _outbox.keys) {
      if (key == _outboxSeqKey) continue;
      final raw = _outbox.get(key);
      if (raw is! Map) continue;
      result.add(
        FavoriteOutboxEntry.fromJson(
          raw.map((mapKey, value) => MapEntry('$mapKey', value)),
        ),
      );
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }

  /// 入队：同一 albumId 只保留最后一次操作（add/remove/add -> 1 条 add）。
  Future<FavoriteOutboxEntry> enqueue(FavoriteOp op, String albumId) async {
    for (final entry in outbox) {
      if (entry.albumId != albumId) continue;
      await _outbox.delete(entry.id);
    }
    final seq = ((_outbox.get(_outboxSeqKey) as num?)?.toInt() ?? 0) + 1;
    await _outbox.put(_outboxSeqKey, seq);
    final entry = FavoriteOutboxEntry(
      id: seq,
      op: op,
      albumId: albumId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _outbox.put(seq, entry.toJson());
    return entry;
  }

  Future<void> removeOutbox(int id) => _outbox.delete(id);

  Future<FavoriteOutboxEntry?> bumpAttempt(int id, String error) async {
    final raw = _outbox.get(id);
    if (raw is! Map) return null;
    final entry = FavoriteOutboxEntry.fromJson(
      raw.map((key, value) => MapEntry('$key', value)),
    );
    final next = entry.copyWith(attempts: entry.attempts + 1, lastError: error);
    await _outbox.put(id, next.toJson());
    return next;
  }

  Future<void> clearOutbox() async {
    await _outbox.clear();
  }
}
