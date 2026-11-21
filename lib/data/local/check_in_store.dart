import 'package:hive_ce/hive.dart';

/// 每日签到的本地存储（纯离线，无网络）。
///
/// 存储结构：Hive box `jm_check_ins`，键为本地日期 `yyyy-MM-dd`，值固定为
/// `true`。同一天重复写入命中同一个键，天然幂等，也不会产生重复记录。
class CheckInStore {
  CheckInStore(this._box, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// 可注入时钟（测试里固定「今天」）。
  final DateTime Function() _clock;

  final Box<dynamic> _box;

  /// 今天（本地时区，时间归零）。
  DateTime get today => normalize(_clock());

  /// 归一化成「只到天」的本地日期。
  static DateTime normalize(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  /// 前 / 后 N 天：用 `DateTime(year, month, day ± delta)` 构造，
  /// 跨月跨年由 DateTime 自己进位，也不受夏令时（23h / 25h 天）影响。
  static DateTime shiftDays(DateTime day, int delta) =>
      DateTime(day.year, day.month, day.day + delta);

  /// 持久化键：`yyyy-MM-dd`。
  static String dayKey(DateTime day) {
    final local = normalize(day);
    final month = local.month.toString().padLeft(2, '0');
    final dayOfMonth = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$dayOfMonth';
  }

  /// 解析持久化键；非本格式一律忽略（防止脏数据影响统计）。
  static DateTime? parseDayKey(Object? key) {
    if (key is! String || key.length != 10) return null;
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return DateTime(year, month, day);
  }

  /// 已签到日期键集合（升序无意义，UI 判定用 Set）。
  Set<String> signedKeys() => <String>{
        for (final key in _box.keys)
          if (parseDayKey(key) != null) key as String,
      };

  /// 已签到日期（按时间升序）。
  List<DateTime> signedDays() {
    final days = <DateTime>[];
    for (final key in _box.keys) {
      final day = parseDayKey(key);
      if (day != null) days.add(day);
    }
    days.sort();
    return days;
  }

  bool isSigned(DateTime day) => _box.containsKey(dayKey(day));

  /// 签到。返回 `true` 表示本次真的新增了一条记录。
  ///
  /// - 未来日期直接拒绝（返回 `false`，不写盘）；
  /// - 同一天重复签到返回 `false`，不产生新记录。
  Future<bool> checkIn(DateTime day) async {
    final target = normalize(day);
    if (target.isAfter(today)) return false;
    final key = dayKey(target);
    if (_box.containsKey(key)) return false;
    await _box.put(key, true);
    return true;
  }

  /// 累计签到天数。
  int totalCount() => signedKeys().length;
}
