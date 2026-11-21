/// 会话状态：本地模式 / 有效 / 失效需重登。
enum SessionState {
  local('local'),
  valid('valid'),
  needsLogin('needs_login');

  const SessionState(this.code);

  final String code;

  static SessionState fromCode(String? code) {
    for (final state in SessionState.values) {
      if (state.code == code) return state;
    }
    return SessionState.local;
  }
}

/// 账号会话快照（`jm_session` box 的 `session` 键）。
///
/// 只存账号展示信息与收藏上限，**不存明文密码**；登录态真正靠 cookie。
class AccountSession {
  const AccountSession({
    this.uid = 0,
    this.username = '',
    this.avatar = '',
    this.favoritesCount = 0,
    this.favoritesMax = 0,
    this.level = 0,
    this.levelName = '',
    this.loggedAt = 0,
    this.state = SessionState.local,
    this.lastSyncAt = 0,
    this.coin = 0,
  });

  final int uid;
  final String username;
  final String avatar;
  final int favoritesCount;
  final int favoritesMax;
  final int level;
  final String levelName;
  final int loggedAt;
  final SessionState state;
  final int lastSyncAt;

  /// JCoin 余额（来自 `/login` 的 `coin` 字段；签到时服务端给的就是这个币）。
  final int coin;

  bool get isLoggedIn => uid > 0 && state == SessionState.valid;

  bool get needsLogin => state == SessionState.needsLogin;

  double get usageRatio => favoritesMax <= 0
      ? 0
      : (favoritesCount / favoritesMax).clamp(0, 1).toDouble();

  bool get nearLimit => favoritesMax > 0 && usageRatio >= 0.9;

  bool get atLimit => favoritesMax > 0 && favoritesCount >= favoritesMax;

  static const AccountSession local = AccountSession();

  AccountSession copyWith({
    int? uid,
    String? username,
    String? avatar,
    int? favoritesCount,
    int? favoritesMax,
    int? level,
    String? levelName,
    int? loggedAt,
    SessionState? state,
    int? lastSyncAt,
    int? coin,
  }) =>
      AccountSession(
        uid: uid ?? this.uid,
        username: username ?? this.username,
        avatar: avatar ?? this.avatar,
        favoritesCount: favoritesCount ?? this.favoritesCount,
        favoritesMax: favoritesMax ?? this.favoritesMax,
        level: level ?? this.level,
        levelName: levelName ?? this.levelName,
        loggedAt: loggedAt ?? this.loggedAt,
        state: state ?? this.state,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        coin: coin ?? this.coin,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'uid': uid,
        'username': username,
        'avatar': avatar,
        'favoritesCount': favoritesCount,
        'favoritesMax': favoritesMax,
        'level': level,
        'levelName': levelName,
        'loggedAt': loggedAt,
        'state': state.code,
        'lastSyncAt': lastSyncAt,
        'coin': coin,
      };

  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
        uid: (json['uid'] as num?)?.toInt() ?? 0,
        username: '${json['username'] ?? ''}',
        avatar: '${json['avatar'] ?? ''}',
        favoritesCount: (json['favoritesCount'] as num?)?.toInt() ?? 0,
        favoritesMax: (json['favoritesMax'] as num?)?.toInt() ?? 0,
        level: (json['level'] as num?)?.toInt() ?? 0,
        levelName: '${json['levelName'] ?? ''}',
        loggedAt: (json['loggedAt'] as num?)?.toInt() ?? 0,
        state: SessionState.fromCode(json['state'] as String?),
        lastSyncAt: (json['lastSyncAt'] as num?)?.toInt() ?? 0,
        coin: (json['coin'] as num?)?.toInt() ?? 0,
      );

  /// 从 `/login` 的解密结果组装；字段缺省时保持 0/空串。
  factory AccountSession.fromLoginJson(
    Map<String, dynamic> json, {
    required int loggedAt,
  }) {
    int intOf(Object? value) {
      if (value is num) return value.toInt();
      return int.tryParse('${value ?? ''}') ?? 0;
    }

    return AccountSession(
      uid: intOf(json['uid']),
      username: '${json['username'] ?? ''}',
      avatar: '${json['photo'] ?? ''}',
      favoritesCount: intOf(json['album_favorites']),
      favoritesMax: intOf(json['album_favorites_max']),
      level: intOf(json['level']),
      levelName: '${json['level_name'] ?? ''}',
      loggedAt: loggedAt,
      state: SessionState.valid,
      coin: intOf(json['coin']),
    );
  }
}
