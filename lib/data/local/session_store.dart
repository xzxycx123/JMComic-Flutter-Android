import 'package:hive_ce/hive.dart';

import '../models/account_session.dart';
import 'hive_init.dart';

/// 会话与 cookie 的持久化（`jm_session`）。
///
/// 只存两样东西：账号快照 + cookie 名值对；**不存密码**。
class SessionStore {
  SessionStore(this._box);

  static const String _keySession = 'session';
  static const String _keyCookies = 'cookies';

  final Box<dynamic> _box;

  AccountSession readSession() {
    final raw = _box.get(_keySession);
    if (raw is! Map) return AccountSession.local;
    return AccountSession.fromJson(raw.map((key, value) => MapEntry('$key', value)));
  }

  Future<void> writeSession(AccountSession session) =>
      _box.put(_keySession, session.toJson());

  Map<String, String> readCookies() {
    final raw = _box.get(_keyCookies);
    if (raw is! Map) return <String, String>{};
    return raw.map((key, value) => MapEntry('$key', '$value'));
  }

  Future<void> writeCookies(Map<String, String> cookies) =>
      _box.put(_keyCookies, cookies);

  Future<void> clear() async {
    await _box.delete(_keySession);
    await _box.delete(_keyCookies);
  }

  /// 失效标记：保留账号展示信息，但把状态改成 needsLogin。
  Future<AccountSession> markNeedsLogin() async {
    final next = readSession().copyWith(state: SessionState.needsLogin);
    await writeSession(next);
    return next;
  }
}

class SessionBoxName {
  static const String name = HiveBoxes.session;
}
