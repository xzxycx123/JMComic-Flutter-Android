import 'jm_album_summary.dart';

/// 收藏条目在「本地账本 + 服务端镜像」之间的同步状态。
enum FavoriteSyncState {
  /// 只在本地（未登录或登录失败）。
  localOnly('local'),

  /// 待推送「加入收藏」。
  pendingAdd('pending_add'),

  /// 待推送「取消收藏」。
  pendingRemove('pending_remove'),

  /// 与服务端一致。
  synced('synced'),

  /// toggle 被服务端反向执行，需要人工/下一轮对账。
  conflict('conflict');

  const FavoriteSyncState(this.code);

  final String code;

  static FavoriteSyncState fromCode(String? code) {
    for (final state in FavoriteSyncState.values) {
      if (state.code == code) return state;
    }
    return FavoriteSyncState.localOnly;
  }

  String get label => switch (this) {
        FavoriteSyncState.localOnly => '仅本地',
        FavoriteSyncState.pendingAdd => '待同步',
        FavoriteSyncState.pendingRemove => '待移除',
        FavoriteSyncState.synced => '已同步',
        FavoriteSyncState.conflict => '待对账',
      };
}

/// 一个收藏记录（`jm_favorites` box 的 value）。
class FavoriteItem {
  const FavoriteItem({
    required this.albumId,
    this.title = '',
    this.author = '',
    this.categoryId = '',
    this.categoryTitle = '',
    this.folderIds = const <String>['default'],
    this.addedAt = 0,
    this.updateAt = 0,
    this.lastSeenAt = 0,
    this.sync = FavoriteSyncState.localOnly,
    this.lastError,
  });

  final String albumId;
  final String title;
  final String author;
  final String categoryId;
  final String categoryTitle;
  final List<String> folderIds;
  final int addedAt;
  final int updateAt;
  final int lastSeenAt;
  final FavoriteSyncState sync;
  final String? lastError;

  bool get hasUpdate => updateAt > 0 && updateAt > lastSeenAt;

  String get displayTitle => title.trim().isEmpty ? 'JM$albumId' : title.trim();

  /// 收藏页/批量下载复用列表卡片模型。
  JmAlbumSummary toSummary() => JmAlbumSummary(
        id: albumId,
        title: title,
        author: author.isEmpty ? 'N/A' : author,
        categoryId: categoryId,
        categoryTitle: categoryTitle,
        updateAt: updateAt,
      );

  FavoriteItem copyWith({
    String? title,
    String? author,
    String? categoryId,
    String? categoryTitle,
    List<String>? folderIds,
    int? addedAt,
    int? updateAt,
    int? lastSeenAt,
    FavoriteSyncState? sync,
    String? lastError,
    bool clearError = false,
  }) =>
      FavoriteItem(
        albumId: albumId,
        title: title ?? this.title,
        author: author ?? this.author,
        categoryId: categoryId ?? this.categoryId,
        categoryTitle: categoryTitle ?? this.categoryTitle,
        folderIds: folderIds ?? this.folderIds,
        addedAt: addedAt ?? this.addedAt,
        updateAt: updateAt ?? this.updateAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        sync: sync ?? this.sync,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'albumId': albumId,
        'title': title,
        'author': author,
        'categoryId': categoryId,
        'categoryTitle': categoryTitle,
        'folderIds': folderIds,
        'addedAt': addedAt,
        'updateAt': updateAt,
        'lastSeenAt': lastSeenAt,
        'sync': sync.code,
        'lastError': lastError,
      };

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    final folders = json['folderIds'];
    return FavoriteItem(
      albumId: '${json['albumId'] ?? ''}',
      title: '${json['title'] ?? ''}',
      author: '${json['author'] ?? ''}',
      categoryId: '${json['categoryId'] ?? ''}',
      categoryTitle: '${json['categoryTitle'] ?? ''}',
      folderIds: folders is List
          ? folders.map((item) => '$item').toList(growable: false)
          : const <String>['default'],
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      updateAt: (json['updateAt'] as num?)?.toInt() ?? 0,
      lastSeenAt: (json['lastSeenAt'] as num?)?.toInt() ?? 0,
      sync: FavoriteSyncState.fromCode(json['sync'] as String?),
      lastError: json['lastError'] as String?,
    );
  }
}

/// 本地收藏夹（v1 只在本地生效；`default` 恒存在）。
class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.name,
    this.order = 0,
    this.createdAt = 0,
  });

  final String id;
  final String name;
  final int order;
  final int createdAt;

  static const FavoriteFolder defaultFolder =
      FavoriteFolder(id: 'default', name: '默认', order: 0);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'order': order,
        'createdAt': createdAt,
      };

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) => FavoriteFolder(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        order: (json['order'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      );
}

/// outbox 操作类型。
enum FavoriteOp {
  add('add'),
  remove('remove');

  const FavoriteOp(this.code);

  final String code;

  static FavoriteOp fromCode(String? code) =>
      code == remove.code ? FavoriteOp.remove : FavoriteOp.add;
}

/// 待推送的收藏操作（`jm_favorite_outbox` box 的 value）。
class FavoriteOutboxEntry {
  const FavoriteOutboxEntry({
    required this.id,
    required this.op,
    required this.albumId,
    this.attempts = 0,
    this.createdAt = 0,
    this.lastError,
  });

  final int id;
  final FavoriteOp op;
  final String albumId;
  final int attempts;
  final int createdAt;
  final String? lastError;

  FavoriteOutboxEntry copyWith({int? attempts, String? lastError, bool clearError = false}) =>
      FavoriteOutboxEntry(
        id: id,
        op: op,
        albumId: albumId,
        attempts: attempts ?? this.attempts,
        createdAt: createdAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'op': op.code,
        'albumId': albumId,
        'attempts': attempts,
        'createdAt': createdAt,
        'lastError': lastError,
      };

  factory FavoriteOutboxEntry.fromJson(Map<String, dynamic> json) => FavoriteOutboxEntry(
        id: (json['id'] as num?)?.toInt() ?? 0,
        op: FavoriteOp.fromCode(json['op'] as String?),
        albumId: '${json['albumId'] ?? ''}',
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
      );
}
