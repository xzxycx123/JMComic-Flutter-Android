import 'json_field.dart';

/// 一条专辑评论（`GET /forum` 的 `list` 项）。
///
/// 字段对齐 jm-mobile `CommentListResponse.ListItem`（实测响应：
/// `{"list":[{"CID":"..","UID":"..","username":"..","nickname":"..","likes":"0",
/// "addtime":"1794625636","parent_CID":"0","content":"..","photo":"..",
/// "spoiler":"0","replys":[]}],"total":"12"}`）。
class JmComment {
  const JmComment({
    required this.id,
    this.albumId = '',
    this.userId = '',
    this.username = '',
    this.nickname = '',
    this.content = '',
    this.avatar = '',
    this.likes = 0,
    this.createdAt = 0,
    this.spoiler = false,
    this.parentId = '0',
    this.replies = const <JmComment>[],
  });

  final String id;
  final String albumId;
  final String userId;
  final String username;
  final String nickname;
  final String content;

  /// 头像路径（多为 `/media/users/...`，需要拼图床域名）。
  final String avatar;
  final int likes;

  /// 秒级时间戳（解析失败为 0）。
  final int createdAt;
  final bool spoiler;
  final String parentId;
  final List<JmComment> replies;

  bool get isReply => parentId.isNotEmpty && parentId != '0';

  String get displayName {
    for (final candidate in <String>[nickname, username]) {
      final value = candidate.trim();
      if (value.isNotEmpty) return value;
    }
    return '匿名';
  }

  /// 列表头像占位字符（无头像时画一个字）。
  String get initial {
    final name = displayName;
    if (name.isEmpty) return '?';
    return String.fromCharCode(name.runes.first);
  }

  /// 「3 分钟前 / 2 小时前 / 11-14」这类紧凑时间。
  String get displayTime {
    if (createdAt <= 0) return '';
    final time = DateTime.fromMillisecondsSinceEpoch(createdAt * 1000);
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    return '${time.year == DateTime.now().year ? '' : '${time.year}-'}$month-$day';
  }

  factory JmComment.fromJson(Map<String, dynamic> json) {
    final replies = asList(json['replys'])
        .map(asMap)
        .whereType<Map<String, dynamic>>()
        .map(JmComment.fromJson)
        .toList(growable: false);
    return JmComment(
      id: asString(json['CID']) ?? '',
      albumId: asString(json['AID']) ?? '',
      userId: asString(json['UID']) ?? '',
      username: (asString(json['username']) ?? '').trim(),
      nickname: (asString(json['nickname']) ?? '').trim(),
      content: (asString(json['content']) ?? '').trim(),
      avatar: (asString(json['photo']) ?? '').trim(),
      likes: asInt(json['likes']),
      createdAt: _parseTimestamp(json['addtime']),
      spoiler: asString(json['spoiler']) == '1',
      parentId: asString(json['parent_CID']) ?? '0',
      replies: replies,
    );
  }

  /// `addtime` 既可能是秒级时间戳，也可能是 `2026-11-14 20:01:33`。
  static int _parseTimestamp(dynamic raw) {
    final text = (asString(raw) ?? '').trim();
    if (text.isEmpty) return 0;
    final numeric = int.tryParse(text);
    if (numeric != null) {
      if (numeric <= 0) return 0;
      return numeric > 99999999999 ? numeric ~/ 1000 : numeric;
    }
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    return parsed == null ? 0 : parsed.millisecondsSinceEpoch ~/ 1000;
  }
}

/// 一页评论。
class JmCommentPage {
  const JmCommentPage({
    this.items = const <JmComment>[],
    this.total = 0,
    this.page = 1,
  });

  final List<JmComment> items;
  final int total;
  final int page;

  static const JmCommentPage empty = JmCommentPage();

  bool get isEmpty => items.isEmpty;

  /// 服务端 total 是总数，按每页 20 条判断是否还有下一页。
  bool hasMore({int pageSize = 20}) {
    if (items.isEmpty) return false;
    if (total <= 0) return items.length >= pageSize;
    return page * pageSize < total;
  }
}
