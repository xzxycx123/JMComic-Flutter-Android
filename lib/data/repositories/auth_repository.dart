import '../../core/network/api_exception.dart';
import '../local/favorites_store.dart';
import '../local/session_store.dart';
import '../models/account_session.dart';
import '../sources/jm_api_client.dart';

/// 登录 / 登出 / 冷启动会话恢复。
///
/// 设计要点（docs/FAVORITES.md §4）：
/// - 登录态靠 cookie，**不存明文密码**；
/// - 冷启动只做一次「cookie + pingFavorite」校验，失败一次即回本地模式；
/// - 登出会清 session + cookie + outbox，本地收藏保留但降级为「仅本地」。
class AuthRepository {
  AuthRepository({
    required JmApi api,
    required SessionStore session,
    required FavoritesStore favorites,
  })  : _api = api,
        _session = session,
        _favorites = favorites;

  final JmApi _api;
  final SessionStore _session;
  final FavoritesStore _favorites;

  AccountSession get snapshot => _session.readSession();

  /// 冷启动：恢复 cookie -> 探一次收藏接口。网络错误不改变登录态。
  Future<AccountSession> restore() async {
    final stored = _session.readSession();
    if (stored.uid <= 0) return AccountSession.local;

    final cookies = _session.readCookies();
    if (cookies.isEmpty) {
      return _session.markNeedsLogin();
    }
    _api.restoreCookies(cookies);

    try {
      final ok = await _api.pingFavorite();
      if (!ok) return await _session.markNeedsLogin();
      return stored.copyWith(state: SessionState.valid);
    } on JmApiException {
      // 只是当前没网：保持上次状态，不要逼用户重登。
      return stored;
    }
  }

  /// 登录：bootstrap -> /login（multipart）-> 校验收藏接口 -> 落 session + cookie。
  Future<AccountSession> login({
    required String username,
    required String password,
  }) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      throw const JmContentException('用户名和密码不能为空');
    }
    await _api.prepare();
    final json = await _api.login(username: name, password: password);
    final session = AccountSession.fromLoginJson(
      json,
      loggedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final ok = await _api.pingFavorite();
    if (!ok) {
      await _session.clear();
      throw const JmContentException('登录校验失败，请检查账号或网络后重试');
    }

    await _session.writeSession(session);
    await persistCookies();
    return session;
  }

  /// 把内存 cookie 写回 Hive（登录成功后、以及每次收藏同步后调用）。
  Future<void> persistCookies() => _session.writeCookies(_api.cookieSnapshot);

  Future<void> logout({bool keepLocalFavorites = true}) async {
    await _session.clear();
    _api.restoreCookies(<String, String>{});
    await _favorites.clearOutbox();
    if (!keepLocalFavorites) {
      await _favorites.clearAll();
    } else {
      await _favorites.demoteSyncedToLocal();
    }
  }

  Future<AccountSession> markNeedsLogin() => _session.markNeedsLogin();
}
