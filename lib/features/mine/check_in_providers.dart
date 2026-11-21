import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../data/local/check_in_store.dart';

/// 签到快照：已签到日期键（`yyyy-MM-dd`）+ 生成快照时的「今天」。
///
/// 「我的」摘要与签到页共用同一个 [checkInProvider]，签到后状态立刻更新，
/// 返回「我的」时不需要额外刷新。
class CheckInState {
  const CheckInState({required this.signedKeys, required this.today});

  final Set<String> signedKeys;
  final DateTime today;

  bool get todayChecked => signedKeys.contains(CheckInStore.dayKey(today));

  /// 累计签到天数。
  int get totalCount => signedKeys.length;

  /// 本月签到次数（以 [today] 所在月份为准）。
  int get monthCount => monthCountOf(today);

  /// 指定月份的签到次数（按 `yyyy-MM` 前缀匹配）。
  int monthCountOf(DateTime month) {
    final prefix = '${month.year}-${month.month.toString().padLeft(2, '0')}-';
    return signedKeys.where((key) => key.startsWith(prefix)).length;
  }

  bool isSigned(DateTime day) => signedKeys.contains(CheckInStore.dayKey(day));

  /// 连续签到天数：今天已签从今天向前数，否则从昨天向前数。
  ///
  /// 逐日回退用 [CheckInStore.shiftDays] 构造日期，跨月、跨年、夏令时都按
  /// 本地日历日进位，不会出现 23 小时差。
  int get streak {
    var cursor = todayChecked ? today : CheckInStore.shiftDays(today, -1);
    var count = 0;
    while (isSigned(cursor)) {
      count++;
      cursor = CheckInStore.shiftDays(cursor, -1);
    }
    return count;
  }
}

final NotifierProvider<CheckInNotifier, CheckInState> checkInProvider =
    NotifierProvider<CheckInNotifier, CheckInState>(CheckInNotifier.new);

class CheckInNotifier extends Notifier<CheckInState> {
  @override
  CheckInState build() => _snapshot();

  CheckInState _snapshot() {
    final store = ref.read(checkInStoreProvider);
    return CheckInState(signedKeys: store.signedKeys(), today: store.today);
  }

  /// 今天签到。返回 `true` 表示本次新增；重复调用幂等（返回 `false`）。
  Future<bool> checkInToday() async {
    final store = ref.read(checkInStoreProvider);
    final added = await store.checkIn(store.today);
    state = _snapshot();
    return added;
  }

  /// 重新读取本地存储（跨天后再进页面时刷新「今天」与统计）。
  void refresh() {
    state = _snapshot();
  }
}
