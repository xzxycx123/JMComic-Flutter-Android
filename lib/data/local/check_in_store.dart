import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../../core/utils/logger.dart';
import '../models/jm_daily.dart';

/// 签到快照缓存（Hive box `jm_check_ins`）。
///
/// 签到本身是**服务端**行为：`GET /daily` 拿当月记录、`POST /daily_chk` 签到领
/// JCoin。这里只缓存「最后一次成功的 `/daily` 响应」按 uid 存一份，用于弱网 /
/// 离线时先把月历画出来，避免整页空白；任何签到动作都不会写这里。
class CheckInStore {
  CheckInStore(this._box);

  final Box<dynamic> _box;

  /// 缓存键：`daily_<uid>`。
  static String keyOf(int userId) => 'daily_$userId';

  /// 读取上次缓存的签到快照；没有或损坏返回 null。
  JmDailyState? read(int userId) {
    if (userId <= 0) return null;
    final raw = _box.get(keyOf(userId));
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      final map = decoded is Map ? decoded : null;
      if (map == null) return null;
      return JmDailyState.fromJson(
        map.map<String, dynamic>((key, value) => MapEntry('$key', value)),
      );
    } catch (error) {
      Log.w('签到快照缓存损坏，忽略：$error');
      return null;
    }
  }

  /// 覆盖写缓存（只在成功拉到服务端记录后调用）。
  Future<void> save(int userId, JmDailyState state) async {
    if (userId <= 0) return;
    await _box.put(keyOf(userId), jsonEncode(state.toJson()));
  }

  Future<void> clear(int userId) async {
    if (userId <= 0) return;
    await _box.delete(keyOf(userId));
  }
}
