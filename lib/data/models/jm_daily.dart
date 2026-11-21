import 'json_field.dart';

/// 签到日历里的一天（服务端 `GET /daily?user_id=<uid>` 的 `record` 项）。
///
/// 服务端原始字段：`{"date":"21","signed":null|true|false,"bonus":true}`。
/// `signed` 为 `null` 表示「未来的日期（还没到 / 不可签）」，统一按未签处理。
class JmDailyDay {
  const JmDailyDay({
    required this.day,
    required this.signed,
    required this.bonus,
  });

  /// 当月第几天（1..31）。
  final int day;
  final bool signed;

  /// 服务端标记的「奖励日」（签了能拿额外奖励）。
  final bool bonus;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'day': day,
        'signed': signed,
        'bonus': bonus,
      };
}

/// 当月签到状态（来自服务端 `GET /daily`，只返回**当前月**）。
class JmDailyState {
  const JmDailyState({
    required this.dailyId,
    required this.rows,
    this.eventName = '',
    this.backgroundPhone = '',
    this.currentProgress = '',
    this.threeDaysCoin = 0,
    this.sevenDaysCoin = 0,
    this.makeupUsed = 0,
    this.makeupLimit = 5,
    this.makeupAvailable = false,
    this.coin,
  });

  /// 签到活动 id：`POST /daily_chk` 必须原样带回去。
  final int dailyId;

  /// 服务端原样的周分组（每行 ≤7 天，从 1 号开始切块）。
  final List<List<JmDailyDay>> rows;

  final String eventName;
  final String backgroundPhone;
  final String currentProgress;
  final int threeDaysCoin;
  final int sevenDaysCoin;

  /// 补签（看广告补签）已用 / 上限。
  final int makeupUsed;
  final int makeupLimit;
  final bool makeupAvailable;

  /// 服务端若在响应里下发 JCoin 余额就带上，否则为 null。
  final int? coin;

  List<JmDailyDay> get days => <JmDailyDay>[
        for (final row in rows) ...row,
      ];

  /// 当月「已签」的日期号集合。
  Set<int> get signedDays => <int>{
        for (final day in days)
          if (day.signed) day.day,
      };

  bool isSigned(int day) => signedDays.contains(day);

  Set<int> get bonusDays => <int>{
        for (final day in days)
          if (day.bonus) day.day,
      };

  JmDailyState copyWith({int? coin}) => JmDailyState(
        dailyId: dailyId,
        rows: rows,
        eventName: eventName,
        backgroundPhone: backgroundPhone,
        currentProgress: currentProgress,
        threeDaysCoin: threeDaysCoin,
        sevenDaysCoin: sevenDaysCoin,
        makeupUsed: makeupUsed,
        makeupLimit: makeupLimit,
        makeupAvailable: makeupAvailable,
        coin: coin ?? this.coin,
      );

  /// 把第 [day] 天标记为已签（签到成功后立刻回显用）。
  JmDailyState withSignedDay(int day) => JmDailyState(
        dailyId: dailyId,
        rows: <List<JmDailyDay>>[
          for (final row in rows)
            <JmDailyDay>[
              for (final cell in row)
                JmDailyDay(
                  day: cell.day,
                  signed: cell.signed || cell.day == day,
                  bonus: cell.bonus,
                ),
            ],
        ],
        eventName: eventName,
        backgroundPhone: backgroundPhone,
        currentProgress: currentProgress,
        threeDaysCoin: threeDaysCoin,
        sevenDaysCoin: sevenDaysCoin,
        makeupUsed: makeupUsed,
        makeupLimit: makeupLimit,
        makeupAvailable: makeupAvailable,
        coin: coin,
      );

  factory JmDailyState.fromJson(Map<String, dynamic> json) {
    final rawRows = asList(json['record'] ?? json['rows']);
    final rows = <List<JmDailyDay>>[];
    for (final rawRow in rawRows) {
      final cells = <JmDailyDay>[];
      for (final rawCell in asList(rawRow)) {
        final cell = asMap(rawCell);
        if (cell == null) continue;
        // 服务端给 `date:"21"`，本地缓存给 `day:21`。
        final day = asInt(cell['day'] ?? cell['date'], 0);
        if (day <= 0) continue;
        cells.add(
          JmDailyDay(
            day: day,
            signed: asBool(cell['signed']),
            bonus: asBool(cell['bonus']),
          ),
        );
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    final rawCoin = json['coin'] ?? json['jCoin'] ?? json['jcoin'];
    return JmDailyState(
      dailyId: asInt(json['daily_id']),
      rows: rows,
      eventName: asString(json['event_name']) ?? '',
      backgroundPhone: asString(json['background_phone']) ?? '',
      currentProgress: asString(json['currentProgress']) ?? '',
      threeDaysCoin: asInt(json['three_days_coin']),
      sevenDaysCoin: asInt(json['seven_days_coin']),
      makeupUsed: asInt(json['makeup_used']),
      makeupLimit: asInt(json['makeup_limit'], 5),
      makeupAvailable: asBool(json['makeup_available']),
      coin: rawCoin == null ? null : asInt(rawCoin),
    );
  }

  /// 缓存到 Hive 用的可逆序列化（键名与 [fromJson] 的本地分支一致）。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'daily_id': dailyId,
        'rows': <dynamic>[
          for (final row in rows)
            <dynamic>[for (final day in row) day.toJson()],
        ],
        'event_name': eventName,
        'background_phone': backgroundPhone,
        'currentProgress': currentProgress,
        'three_days_coin': threeDaysCoin,
        'seven_days_coin': sevenDaysCoin,
        'makeup_used': makeupUsed,
        'makeup_limit': makeupLimit,
        'makeup_available': makeupAvailable,
        if (coin != null) 'coin': coin,
      };
}

/// `POST /daily_chk` 的结果。
///
/// 服务端成功时只回一句文案（`data.msg`，例如「簽到成功」/「已經簽到過了」），
/// 也可能什么都不回 —— 所以调用方要再用 `GET /daily` 核对今天的 `signed`，
/// 以及（如果响应里带了）最新的 JCoin 余额。
class JmCheckInResult {
  const JmCheckInResult({
    required this.message,
    required this.alreadySigned,
    this.coin,
  });

  final String message;

  /// 服务端文案表明「今天已经签过」。
  final bool alreadySigned;

  /// 签到响应里若顺带下发 JCoin 余额就带上（不是所有版本都回）。
  final int? coin;

  bool get hasMessage => message.trim().isNotEmpty;
}
