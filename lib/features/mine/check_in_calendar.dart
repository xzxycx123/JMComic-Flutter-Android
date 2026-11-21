import '../../data/local/check_in_store.dart';

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
  });

  final DateTime date;

  /// 是否属于当前展示的月份（前后补齐的邻月日期为 `false`）。
  final bool inMonth;
  final bool isToday;
  final bool signed;
}

/// 生成 [month] 所在月份的月历，按周分组，每组 7 格，周一起始。
///
/// 首行用上月日期补齐到周一，末行补到周日，因此行数 = ceil((leading + 天数) / 7)。
List<List<CheckInDayCell>> buildCheckInWeeks({
  required DateTime month,
  required DateTime today,
  required bool Function(DateTime day) isSigned,
}) {
  final firstOfMonth = DateTime(month.year, month.month);
  final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
  // DateTime.monday == 1，直接取模得到「周一起始」的偏移（周一 -> 0）。
  final leading = (firstOfMonth.weekday - DateTime.monday) % 7;
  final weekCount = (leading + daysInMonth + 6) ~/ 7;
  final gridStart = CheckInStore.shiftDays(firstOfMonth, -leading);
  final todayKey = CheckInStore.dayKey(today);

  return <List<CheckInDayCell>>[
    for (var week = 0; week < weekCount; week++)
      <CheckInDayCell>[
        for (var index = 0; index < 7; index++)
          _cellAt(
            CheckInStore.shiftDays(gridStart, week * 7 + index),
            month: firstOfMonth,
            todayKey: todayKey,
            isSigned: isSigned,
          ),
      ],
  ];
}

CheckInDayCell _cellAt(
  DateTime date, {
  required DateTime month,
  required String todayKey,
  required bool Function(DateTime day) isSigned,
}) {
  return CheckInDayCell(
    date: date,
    inMonth: date.year == month.year && date.month == month.month,
    isToday: CheckInStore.dayKey(date) == todayKey,
    signed: isSigned(date),
  );
}
