import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
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

  /// 冷启动：恢复 cookie -> 跑一次 /setting -> 探一次收藏接口。
  ///
  /// 0.3.1 修复「每次退出 App 就掉登录」：
  /// 1. 校验前**必须**先跑 `/setting`（站点会轮换它下发的 cookie，只拿上次的快照
  ///    去打 `/favorite` 很容易被判未登录）；
  /// 2. 只有服务端**明确**说未登录 / 401 / 会话失效才降级成 `needsLogin`，
  ///    其它业务错误与网络错误一律保持登录态（宁可下次操作报错，也不把用户踢下线）。
  Future<AccountSession> restore() async {
    final stored = _session.readSession();
    if (stored.uid <= 0) return AccountSession.local;

    final cookies = _session.readCookies();
    if (cookies.isEmpty) {
      return _session.markNeedsLogin();
    }
    // 本进程内如果已经跑过 /setting（jar 里是新 cookie），不要用 Hive 的旧快照覆盖它。
    if (_api.cookieSnapshot.isEmpty) {
      _api.restoreCookies(cookies);
    }

    try {
      // 已经引导过（本进程）就不再重复 discovery + /setting。
      if (!_api.session.ready) await _api.prepare();
    } on JmApiException catch (error) {
      Log.w('冷启动 /setting 失败，保持登录态：$error');
      return stored;
    }

    try {
      await _api.fetchFavorites(page: 1);
      // /setting / /favorite 这一轮很可能已经把 cookie 轮换了，立刻回写。
      await persistCookies();
      return stored.copyWith(state: SessionState.valid);
    } on JmContentException catch (error) {
      if (_looksLikeAuthFailure(error.message)) {
        return _session.markNeedsLogin();
      }
      Log.w('冷启动校验返回业务错误，保持登录态：${error.message}');
      return stored.copyWith(state: SessionState.valid);
    } on JmApiException {
      // 只是当前没网：保持上次状态，不要逼用户重登。
      return stored;
    }
  }

  /// 业务文案里出现这些才算「会话真的失效」；其余都当作可重试错误。
  static bool _looksLikeAuthFailure(String message) {
    final text = message.toLowerCase();
    for (final needle in const <String>[
      '未登入',
      '未登录',
      '未登錄',
      '请先登入',
      '请先登录',
      '請先登入',
      '請先登錄',
      '登录已失效',
      '登录状态已失效',
      'not login',
      'unauthorized',
      '401',
    ]) {
      if (text.contains(needle.toLowerCase())) return true;
    }
    return false;
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

    final Map<String, dynamic> json;
    try {
      json = await _api.login(username: name, password: password);
    } on JmContentException catch (error) {
      throw JmContentException(describeLoginFailure(error.message), cause: error);
    } on JmApiException catch (error) {
      throw JmApiException('网络异常，登录请求没发出去：${error.message}', cause: error);
    }

    final session = AccountSession.fromLoginJson(
      json,
      loggedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (session.uid <= 0) {
      throw const JmContentException('登录失败：服务端没有返回账号信息');
    }

    final bool ok;
    try {
      ok = await _api.pingFavorite();
    } on JmApiException catch (error) {
      // /login 已经成功，只是校验接口这一刻不通（离线 / 线路抖动）：
      // 先落盘，把「同步失败」留给登录后的同步提示，别让用户白输一次密码。
      Log.w('登录后校验收藏接口失败（按已登录处理）：$error');
      await _session.writeSession(session);
      await persistCookies();
      return session;
    }
    if (!ok) {
      // 校验拿到的是业务错误（不是 401）：同样不推翻 /login 的成功结果，
      // 只记一条日志；真失效了下次操作会再报，用户也能在「我的」里看到状态。
      Log.w('登录后校验返回业务错误，仍按登录成功处理');
    }

    await _session.writeSession(session);
    await persistCookies();
    return session;
  }

  /// 把服务端原文翻译成用户能看懂的一句话（登录失败提示框直接用它）。
  static String describeLoginFailure(String raw) {
    final message = raw.trim();
    final lower = message.toLowerCase();
    if (message.contains('登录状态已失效')) return '用户名或密码不正确';
    if (lower.contains('password') || message.contains('密碼') || message.contains('密码')) {
      return '用户名或密码不正确';
    }
    if (message.contains('频繁') || lower.contains('too many') || lower.contains('rate')) {
      return '请求太频繁，请等一会儿再试';
    }
    if (message.contains('人机') || lower.contains('cloudflare') || message.contains('驗證')) {
      return '触发了站点人机校验，请换一条线路或稍后再试';
    }
    if (message.contains('未激活') || message.contains('封')) {
      return message;
    }
    if (message.isEmpty) return '登录失败，请稍后再试';
    return message.replaceFirst(RegExp(r'^JM 接口错误[:：]\s*'), '');
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
