import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
import '../local/credential_store.dart';
import '../local/favorites_store.dart';
import '../local/session_store.dart';
import '../models/account_session.dart';
import '../sources/jm_api_client.dart';

/// 登录 / 登出 / 冷启动会话恢复 / 记住密码自动重登。
///
/// 三层兜底（0.3.2 起）：
/// 1. cookie 持久化 + 冷启动 `/setting` 刷新（0.3.1 已有）；
/// 2. cookie 失效时用系统密钥库里的账号密码**自动重登一次**；
/// 3. 仍失败才降级 `needsLogin`，本地收藏照常可用。
class AuthRepository {
  AuthRepository({
    required JmApi api,
    required SessionStore session,
    required FavoritesStore favorites,
    CredentialVault? vault,
    bool Function()? rememberPassword,
  })  : _api = api,
        _session = session,
        _favorites = favorites,
        _vault = vault,
        _rememberPassword = rememberPassword ?? (() => true);

  final JmApi _api;
  final SessionStore _session;
  final FavoritesStore _favorites;
  final CredentialVault? _vault;
  final bool Function() _rememberPassword;

  AccountSession get snapshot => _session.readSession();

  /// 冷启动：恢复 cookie -> /setting -> 探收藏接口；任一环节判定会话失效就自动重登。
  ///
  /// 0.3.1 修复「每次退出 App 就掉登录」：
  /// 1. 校验前**必须**先跑 `/setting`（站点会轮换它下发的 cookie，只拿上次的快照
  ///    去打 `/favorite` 很容易被判未登录）；
  /// 2. 只有服务端**明确**说未登录 / 401 / 会话失效才降级，其它错误保持登录态。
  Future<AccountSession> restore() async {
    final stored = _session.readSession();
    if (stored.uid <= 0) {
      // 会话记录没了（用户主动登出过就不该自动登录）：只有存了密码才救一次。
      return _autoLoginOr(AccountSession.local);
    }

    final cookies = _session.readCookies();
    if (cookies.isEmpty) {
      return _autoLoginOr(await _session.markNeedsLogin());
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
        return _autoLoginOr(await _session.markNeedsLogin());
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

  /// 用保存的密码静默重登；没有凭据或失败就返回 [fallback]。
  Future<AccountSession> _autoLoginOr(AccountSession fallback) async {
    final session = await autoLogin();
    if (session != null && session.isLoggedIn) return session;
    return fallback;
  }

  /// 自动重登（登录门槛/同步失败时也可直接调用）。无凭据或失败返回 null。
  ///
  /// 成功后本地收藏按新会话重新对账（由调用方触发，避免这里耦合同步引擎）。
  Future<AccountSession?> autoLogin() async {
    final vault = _vault;
    if (vault == null) return null;
    final credential = await vault.read();
    if (credential == null) return null;
    if (!_rememberPassword()) {
      Log.i('未开启「记住密码」，跳过自动登录');
      return null;
    }
    try {
      final session = await login(
        username: credential.username,
        password: credential.password,
        remember: true,
      );
      Log.i('已用保存的密码自动登录：${session.username}');
      return session;
    } catch (error) {
      Log.w('自动登录失败：$error');
      return null;
    }
  }

  /// 登录：bootstrap -> /login（multipart）-> 校验收藏接口 -> 落 session + cookie。
  ///
  /// [remember] 为 true（默认跟设置走）时把账号密码写进系统密钥库，供下次自动重登。
  Future<AccountSession> login({
    required String username,
    required String password,
    bool? remember,
  }) async {
    final name = username.trim();
    if (name.isEmpty || password.isEmpty) {
      throw const JmContentException('用户名和密码不能为空');
    }
    if (!_api.session.ready) await _api.prepare();

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

    try {
      final ok = await _api.pingFavorite();
      if (!ok) {
        // 校验拿到的是业务错误（不是 401）：同样不推翻 /login 的成功结果，
        // 只记一条日志；真失效了下次操作会再报，用户也能在「我的」里看到状态。
        Log.w('登录后校验返回业务错误，仍按登录成功处理');
      }
    } on JmApiException catch (error) {
      // /login 已经成功，只是校验接口这一刻不通（离线 / 线路抖动）：
      // 先落盘，把「同步失败」留给登录后的同步提示，别让用户白输一次密码。
      Log.w('登录后校验收藏接口失败（按已登录处理）：$error');
    }

    await _session.writeSession(session);
    await persistCookies();

    final shouldRemember = remember ?? _rememberPassword();
    if (shouldRemember) {
      await _vault?.save(
        SavedCredential(username: name, password: password),
      );
    } else {
      await _vault?.clear();
    }
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

  /// 清掉保存的账号密码（用户关掉「记住密码」或主动登出）。
  Future<void> forgetPassword() => _vault?.clear() ?? Future<void>.value();

  Future<void> logout({bool keepLocalFavorites = true}) async {
    // 主动登出要连保存的密码一起清掉，否则下次冷启动又被自动登回去。
    await forgetPassword();
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
