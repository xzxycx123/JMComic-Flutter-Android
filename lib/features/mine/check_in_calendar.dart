import '../../data/models/jm_daily.dart';

/// 月历表头：周一起始。
const List<String> kCheckInWeekdayLabels = <String>[
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

/// 月历里的一个日期格子。
class CheckInDayCell {
  const CheckInDayCell({
    required this.date,
    required this.inMonth,
    required this.isToday,
    required this.signed,
    this.bonus = false,
    this.future = false,
  });

  final DateTime date;

  /// 是否属于当前展示的月份（前后补齐的邻月日期为 `false`）。
  final bool inMonth;
  final bool isToday;

  /// 服务端记录里这天已签到。
  final bool signed;

  /// 服务端标记的奖励日。
  final bool bonus;

  /// 今天之后的日期（不可签）。
  final bool future;
}

/// 生成 [month] 所在月份的月历，按周分组，每组 7 格，周一起始。
///
/// 首行用上月日期补齐到周一，末行补到周日，因此行数 = ceil((leading + 天数) / 7)。
///
/// 签到数据来自服务端当月记录：[daily] 里只有「当月第几天 -> 是否已签 / 是否奖励
/// 日」，本函数负责把「几号」摆到正确星期上。
List<List<CheckInDayCell>> buildCheckInWeeks({
  required DateTime month,
  required DateTime today,
  JmDailyState? daily,
  bool Function(DateTime day)? isSigned,
}) {
  final firstOfMonth = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  // DateTime.monday == 1，直接取模得到「周一起始」的偏移（周一 -> 0）。
  final leading = (firstOfMonth.weekday - DateTime.monday) % 7;
  final weekCount = (leading + daysInMonth + 6) ~/ 7;
  final gridStart = DateTime(
    firstOfMonth.year,
    firstOfMonth.month,
    firstOfMonth.day - leading,
  );
  final todayDay = DateTime(today.year, today.month, today.day);
  final signedDays = daily?.signedDays ?? const <int>{};
  final bonusDays = daily?.bonusDays ?? const <int>{};
  final isSameMonth =
      month.year == todayDay.year && month.month == todayDay.month;

  bool signedOn(DateTime date) {
    if (isSigned != null) return isSigned(date);
    if (!isSameMonth) return false;
    return signedDays.contains(date.day);
  }

  bool bonusOn(DateTime date) => isSameMonth && bonusDays.contains(date.day);

  return <List<CheckInDayCell>>[
    for (var week = 0; week < weekCount; week++)
      <CheckInDayCell>[
        for (var index = 0; index < 7; index++)
          _cellAt(
            DateTime(
              gridStart.year,
              gridStart.month,
              gridStart.day + week * 7 + index,
            ),
            month: firstOfMonth,
            today: todayDay,
            signedOn: signedOn,
            bonusOn: bonusOn,
          ),
      ],
  ];
}

CheckInDayCell _cellAt(
  DateTime date, {
  required DateTime month,
  required DateTime today,
  required bool Function(DateTime date) signedOn,
  required bool Function(DateTime date) bonusOn,
}) {
  final inMonth = date.year == month.year && date.month == month.month;
  return CheckInDayCell(
    date: date,
    inMonth: inMonth,
    isToday: date == today,
    signed: inMonth && signedOn(date),
    bonus: inMonth && bonusOn(date),
    future: date.isAfter(today),
  );
}
