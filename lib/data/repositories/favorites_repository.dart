import 'dart:async';

import '../../core/network/api_exception.dart';
import '../local/favorites_store.dart';
import '../local/session_store.dart';
import '../models/account_session.dart';
import '../models/favorite_item.dart';
import '../models/jm_album_summary.dart';
import '../sources/jm_api_client.dart';

/// 一次同步的结果（设置页 / 我的页展示用）。
class FavoriteSyncReport {
  const FavoriteSyncReport({
    this.addedToLocal = 0,
    this.pushed = 0,
    this.failures = 0,
    this.conflicts = 0,
    this.serverCount = 0,
    this.message = '',
  });

  final int addedToLocal;
  final int pushed;
  final int failures;
  final int conflicts;
  final int serverCount;
  final String message;
}

/// 收藏：本地账本 + 服务端镜像（toggle 对账）。
///
/// 红线（docs/FAVORITES.md §0）：写本地、读本地；服务端只同步布尔；toggle 必须对账。
class FavoritesRepository {
  FavoritesRepository({
    required JmApi api,
    required FavoritesStore store,
    required SessionStore session,
  })  : _api = api,
        _store = store,
        _session = session;

  final JmApi _api;
  final FavoritesStore _store;
  final SessionStore _session;

  FavoritesStore get store => _store;

  List<FavoriteItem> get items => _store.items;

  List<FavoriteFolder> get folders => _store.folders;

  List<FavoriteOutboxEntry> get outbox => _store.outbox;

  int get count => _store.count;

  bool isFavorite(String albumId) => _store.contains(albumId);

  AccountSession get session => _session.readSession();

  /// 收藏按钮：乐观更新，已登录时入 outbox 并尽力立即推送。
  ///
  /// 返回 true 表示「本次变成了已收藏」。
  Future<bool> toggle(
    JmAlbumSummary album, {
    String folderId = 'default',
  }) async {
    final exists = _store.contains(album.id);
    final loggedIn = session.isLoggedIn;

    if (exists) {
      await _store.remove(album.id);
      if (loggedIn) {
        await _store.enqueue(FavoriteOp.remove, album.id);
        unawaited(pushOutbox());
      }
      return false;
    }

    await _store.addFromSummary(
      album,
      folderId: folderId,
      sync: loggedIn ? FavoriteSyncState.pendingAdd : FavoriteSyncState.localOnly,
    );
    if (loggedIn) {
      await _store.enqueue(FavoriteOp.add, album.id);
      unawaited(pushOutbox());
    }
    return true;
  }

  /// 撤销一次 toggle（SnackBar 的「撤销」用）。
  Future<void> undo(bool wasAdded, JmAlbumSummary album) async {
    if (wasAdded) {
      await _store.remove(album.id);
      for (final entry in _store.outbox) {
        if (entry.albumId == album.id) await _store.removeOutbox(entry.id);
      }
    } else {
      await _store.addFromSummary(album);
    }
  }

  Future<void> remove(String albumId) async {
    await _store.remove(albumId);
    if (!session.isLoggedIn) return;
    await _store.enqueue(FavoriteOp.remove, albumId);
    unawaited(pushOutbox());
  }

  Future<FavoriteFolder> createFolder(String name) => _store.createFolder(name);

  Future<void> deleteFolder(String folderId) => _store.deleteFolder(folderId);

  Future<void> moveToFolder(String albumId, String folderId) =>
      _store.assignFolder(albumId, folderId);

  Future<void> removeFromFolder(String albumId, String folderId) =>
      _store.removeFromFolder(albumId, folderId);

  Future<void> markSeen(String albumId) =>
      _store.setLastSeen(albumId, DateTime.now().millisecondsSinceEpoch);

  // ---------------------------------------------------------------- 同步
  /// 对账 + 推送。未登录时抛 [JmContentException]，由调用方提示登录。
  Future<FavoriteSyncReport> sync() async {
    if (!session.isLoggedIn) {
      throw const JmContentException('未登录，收藏只能在本地使用');
    }
    final reconciled = await _reconcile();
    final pushed = await pushOutbox();
    final account = session;
    await _session.writeSession(
      account.copyWith(
        lastSyncAt: DateTime.now().millisecondsSinceEpoch,
        favoritesCount: reconciled.serverCount,
      ),
    );
    return FavoriteSyncReport(
      addedToLocal: reconciled.addedToLocal,
      pushed: pushed.pushed,
      failures: pushed.failures + reconciled.failures,
      conflicts: pushed.conflicts,
      serverCount: reconciled.serverCount,
      message: '对账完成：服务端 ${reconciled.serverCount} 本',
    );
  }

  Future<({int addedToLocal, int serverCount, int failures})> _reconcile() async {
    final serverItems = <String, JmAlbumSummary>{};
    var serverCount = 0;
    for (var page = 1; page <= 100; page++) {
      final result = await _api.fetchFavorites(page: page);
      serverCount = result.count > 0 ? result.count : serverCount;
      if (result.items.isEmpty) break;
      for (final item in result.items) {
        serverItems[item.id] = item;
      }
      // 风控保护：页间隔 300ms。
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    var addedToLocal = 0;
    final localItems = _store.items;

    // 服务端有、本地没有 -> 落本地（已同步）。
    for (final entry in serverItems.entries) {
      if (_store.contains(entry.key)) continue;
      await _store.addFromSummary(entry.value, sync: FavoriteSyncState.synced);
      addedToLocal++;
    }

    // 本地与服务器逐条对齐。
    for (final item in localItems) {
      final remote = serverItems[item.albumId];
      if (remote == null) {
        if (item.sync == FavoriteSyncState.pendingRemove) {
          await _store.remove(item.albumId);
        } else if (item.sync != FavoriteSyncState.conflict) {
          await _store.setSync(item.albumId, FavoriteSyncState.pendingAdd);
          await _store.enqueue(FavoriteOp.add, item.albumId);
        }
        continue;
      }
      // 两边都有：回填标题/更新时间，本地文件夹保留。
      await _store.put(
        item
            .copyWith(
              title: item.title.isEmpty ? remote.title : item.title,
              author: item.author.isEmpty ? remote.authorName : item.author,
              categoryId: item.categoryId.isEmpty ? remote.categoryId : item.categoryId,
              categoryTitle:
                  item.categoryTitle.isEmpty ? remote.categoryTitle : item.categoryTitle,
              updateAt: remote.updateAt > 0 ? remote.updateAt : item.updateAt,
              sync: FavoriteSyncState.synced,
            )
            .copyWith(clearError: true),
      );
    }

    return (addedToLocal: addedToLocal, serverCount: serverCount, failures: 0);
  }

  /// 串行推送 outbox；toggle 返回与预期相反时立刻反向补发一次。
  Future<({int pushed, int failures, int conflicts})> pushOutbox() async {
    var pushed = 0;
    var failures = 0;
    var conflicts = 0;
    var consecutiveBusinessFailures = 0;

    for (final entry in _store.outbox) {
      if (entry.attempts >= 5) {
        failures++;
        continue;
      }
      final expected = entry.op == FavoriteOp.add ? 'add' : 'remove';
      try {
        final actual = await _api.toggleFavorite(entry.albumId);
        if (actual != expected) {
          // 服务端状态被切反了：再切一次扳回来，并标记待对账。
          await _api.toggleFavorite(entry.albumId);
          await _store.setSync(entry.albumId, FavoriteSyncState.conflict);
          await _store.removeOutbox(entry.id);
          conflicts++;
          continue;
        }
        if (entry.op == FavoriteOp.add) {
          await _store.setSync(entry.albumId, FavoriteSyncState.synced);
        } else {
          await _store.remove(entry.albumId);
        }
        await _store.removeOutbox(entry.id);
        pushed++;
        consecutiveBusinessFailures = 0;
      } on JmApiException {
        // 网络异常：保留 outbox，下次继续。
        await _store.bumpAttempt(entry.id, '网络异常，待重试');
        failures++;
        break;
      } on JmContentException catch (error) {
        await _store.bumpAttempt(entry.id, error.message);
        failures++;
        consecutiveBusinessFailures++;
        if (consecutiveBusinessFailures >= 3) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    await _session.writeCookies(_api.cookieSnapshot);
    return (pushed: pushed, failures: failures, conflicts: conflicts);
  }
}
