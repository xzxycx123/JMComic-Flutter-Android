import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/app.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/data/local/check_in_store.dart';
import 'package:jm_comic/data/local/download_store.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/account_session.dart';
import 'package:jm_comic/data/models/jm_daily.dart';
import 'package:jm_comic/data/repositories/home_repository.dart';
import 'package:jm_comic/features/collect/collect_providers.dart';
import 'package:jm_comic/features/mine/check_in_calendar.dart';
import 'package:jm_comic/features/mine/check_in_providers.dart';
import 'package:jm_comic/features/mine/daily_check_in_page.dart';
import 'package:jm_comic/features/shell/glass_nav_bar.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

/// 设置存储的内存替身（避开 SharedPreferences / Hive 的真实 IO）。
class _MemorySettingsStore extends Fake implements SettingsStore {
  AppSettings _settings = const AppSettings();

  @override
  AppSettings read() => _settings;

  @override
  Future<void> write(AppSettings settings) async {
    _settings = settings;
  }
}

/// 固定登录态的账号 notifier（头像栏 JCoin 展示测试用）。
class _FakeAccountNotifier extends AccountSessionNotifier {
  _FakeAccountNotifier(this.session);

  final AccountSession session;

  @override
  Future<AccountSession> build() async => session;
}

/// 内存版 Box：widget 测试里 Hive 的真实文件写入跑在 fake async 下会挂住。
class _MemoryBox extends Fake implements Box<dynamic> {
  final Map<dynamic, dynamic> _data = <dynamic, dynamic>{};

  @override
  Iterable<dynamic> get keys => _data.keys;

  @override
  bool containsKey(dynamic key) => _data.containsKey(key);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _data.containsKey(key) ? _data[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(dynamic key) async {
    _data.remove(key);
  }

  @override
  bool get isEmpty => _data.isEmpty;

  @override
  bool get isNotEmpty => _data.isNotEmpty;

  @override
  int get length => _data.length;
}

/// 固定「今天」= 2026-11-21。
DateTime get _today => DateTime(2026, 11, 21, 10);

const AccountSession _loggedIn = AccountSession(
  uid: 4242,
  username: 'tester',
  state: SessionState.valid,
  coin: 120,
);

/// 服务端 `/daily` 的样子（2026-11-21 实测结构，30 天，20、21 已签）。
JmDailyState _serverDaily({Set<int> signed = const <int>{20, 21}}) =>
    buildFakeDaily(signed: signed, bonus: const <int>{21}, coin: 150);

/// 工单四（重做）：每日签到 = 服务端行为（GET /daily + POST /daily_chk）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Box<dynamic> box;

  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
    box = Hive.box<dynamic>(HiveBoxes.checkIns);
  });

  ProviderContainer containerFor({
    FakeJmApi? api,
    AccountSession? account = _loggedIn,
    CheckInStore? store,
    DateTime Function()? clock,
    List<int>? coinSink,
  }) {
    final fake = api ?? FakeJmApi(loggedIn: true);
    final sink = coinSink ?? <int>[];
    return ProviderContainer(
      overrides: <Override>[
        checkInAccountProvider.overrideWithValue(account),
        jmBootstrapProvider.overrideWith((ref) async => fake),
        checkInClockProvider.overrideWithValue(clock ?? () => _today),
        checkInCoinSinkProvider.overrideWithValue((coin) async {
          sink.add(coin);
        }),
        if (store != null) checkInStoreProvider.overrideWithValue(store),
      ],
    );
  }

  group('服务端协议', () {
    test('/daily 的 record 解析：signed=null 按未签处理、daily_id 保留', () {
      final state = JmDailyState.fromJson(<String, dynamic>{
        'daily_id': 74,
        'three_days_coin': '30',
        'seven_days_coin': '500',
        'event_name': '11月-兔兔萬歲',
        'currentProgress': '0%',
        'makeup_used': 0,
        'makeup_limit': 5,
        'makeup_available': true,
        'record': <dynamic>[
          <dynamic>[
            <String, dynamic>{'date': '01', 'signed': false, 'bonus': true},
            <String, dynamic>{'date': '02', 'signed': true, 'bonus': false},
          ],
          <dynamic>[
            <String, dynamic>{'date': '21', 'signed': null, 'bonus': true},
          ],
        ],
      });

      expect(state.dailyId, 74);
      expect(state.eventName, '11月-兔兔萬歲');
      expect(state.threeDaysCoin, 30);
      expect(state.sevenDaysCoin, 500);
      expect(state.makeupLimit, 5);
      expect(state.makeupAvailable, isTrue);
      expect(state.signedDays, <int>{2});
      expect(state.isSigned(21), isFalse, reason: 'signed=null 是未来日期');
      expect(state.bonusDays, <int>{1, 21});
    });

    test('缓存的 toJson / fromJson 往返一致', () {
      final source = _serverDaily();
      final restored = JmDailyState.fromJson(source.toJson());
      expect(restored.dailyId, source.dailyId);
      expect(restored.signedDays, source.signedDays);
      expect(restored.bonusDays, source.bonusDays);
      expect(restored.coin, source.coin);
      expect(restored.makeupLimit, source.makeupLimit);
    });

    test('登录响应的 coin 落到账号快照（头像栏 JCoin 来源）', () {
      final session = AccountSession.fromLoginJson(
        <String, dynamic>{
          'uid': 42,
          'username': 'tester',
          'coin': 320,
          'album_favorites': 3,
          'album_favorites_max': 500,
        },
        loggedAt: 1,
      );
      expect(session.coin, 320);
      expect(AccountSession.fromJson(session.toJson()).coin, 320);
    });
  });

  group('月历生成', () {
    test('周一起始、只统计本月、今天标记、服务端已签映射到位', () {
      final daily = _serverDaily();
      final weeks = buildCheckInWeeks(
        month: _today,
        today: _today,
        daily: daily,
      );
      final cells = weeks.expand((week) => week).toList();

      expect(weeks.every((week) => week.length == 7), isTrue);
      // 2026-11-01 是周日 -> 首格补到 10-26（周一）。
      expect(weeks.first.first.date.weekday, DateTime.monday);
      expect(weeks.first.first.date, DateTime(2026, 10, 26));
      expect(cells.where((cell) => cell.inMonth).length, 30);
      final todayCell = cells.where((cell) => cell.isToday).single;
      expect(todayCell.date, DateTime(2026, 11, 21));
      expect(todayCell.signed, isTrue);
      expect(todayCell.bonus, isTrue);
      expect(
        cells.where((cell) => cell.signed).map((cell) => cell.date.day),
        <int>[20, 21],
      );
      // 未来日期标记（不可签）。
      expect(cells.firstWhere((cell) => cell.date.day == 22).future, isTrue);
    });
  });

  group('provider（服务端签到）', () {
    test('未登录：不请求 /daily，签到直接被拦', () async {
      final api = FakeJmApi();
      final container =
          containerFor(api: api, account: null, store: CheckInStore(box));
      addTearDown(container.dispose);

      final state = container.read(checkInProvider);
      expect(state.loggedIn, isFalse);
      expect(state.hasData, isFalse);

      final outcome = await container.read(checkInProvider.notifier).checkIn();
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('登录'));
      expect(api.dailyCalls, 0);
      expect(api.dailyCheckInCalls, 0);
    });

    test('登录后拉取当月记录：本月已签 / 连续天数来自服务端', () async {
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = _serverDaily(signed: const <int>{20});
      final store = CheckInStore(_MemoryBox());
      final container = containerFor(api: api, store: store);
      addTearDown(container.dispose);

      // 先 read 触发 build（它才会排微任务去拉 /daily），再等异步完成。
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);
      final state = container.read(checkInProvider);
      expect(api.dailyCalls, 1);
      expect(state.loggedIn, isTrue);
      expect(state.hasData, isTrue);
      expect(state.todayChecked, isFalse);
      expect(state.monthCount, 1);
      expect(state.streak, 1, reason: '今天未签 -> 从昨天(20)往前数 1 天');
      expect(state.coin, 150, reason: '/daily 下发的 JCoin 优先');
      expect(state.host, 'www.cdnbtd.cc', reason: '记录实际打通的接口线路');

      // 快照落到缓存（离线可回显）。
      expect(store.read(4242)?.signedDays, <int>{20});
    });

    test('签到：POST /daily_chk 带 user_id + daily_id，随后以 /daily 核对', () async {
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = _serverDaily(signed: const <int>{});
      final container =
          containerFor(api: api, store: CheckInStore(_MemoryBox()));
      addTearDown(container.dispose);
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);

      expect(container.read(checkInProvider).todayChecked, isFalse);
      final outcome = await container.read(checkInProvider.notifier).checkIn();

      expect(outcome.success, isTrue);
      expect(outcome.message, '簽到成功');
      expect(api.dailyCheckInCalls, 1);
      expect(api.dailyCheckInPayloads.single, 'user_id=4242&daily_id=74');
      final state = container.read(checkInProvider);
      expect(state.todayChecked, isTrue);
      expect(state.streak, 1);
      expect(state.monthCount, 1);
    });

    test('签到响应带 JCoin 余额时立即落到状态里（/daily 不回 coin 也认）', () async {
      final api = FakeJmApi(loggedIn: true)
        ..dailyToday = 21
        ..dailyCheckInCoin = 175;
      // 故意用不带 coin 的 /daily，验证余额来自签到响应本身。
      api.dailyState = buildFakeDaily();
      final coinSink = <int>[];
      final container = containerFor(
        api: api,
        store: CheckInStore(_MemoryBox()),
        coinSink: coinSink,
      );
      addTearDown(container.dispose);
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);

      final outcome = await container.read(checkInProvider.notifier).checkIn();
      expect(outcome.success, isTrue);
      expect(container.read(checkInProvider).coin, 175);
      expect(container.read(checkInProvider).todayChecked, isTrue);
      expect(coinSink, contains(175), reason: '余额要回写到账号快照（头像栏）');
    });

    test('服务端说「已經簽到過了」且没生效：不谎报成功', () async {
      final api = FakeJmApi(loggedIn: true)
        ..dailyToday = 21
        ..dailyCheckInApplies = false
        ..dailyCheckInMessage = '今天已經簽到過了';
      api.dailyState = _serverDaily(signed: const <int>{});
      final container =
          containerFor(api: api, store: CheckInStore(_MemoryBox()));
      addTearDown(container.dispose);
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);

      final outcome = await container.read(checkInProvider.notifier).checkIn();
      expect(outcome.success, isFalse);
      expect(outcome.alreadySigned, isTrue);
      expect(outcome.message, contains('已經簽到過了'));
      expect(container.read(checkInProvider).todayChecked, isFalse);
    });

    test('签到接口报错：抛出文案进 outcome 与 error', () async {
      final api = FakeJmApi(loggedIn: true)
        ..dailyToday = 21
        ..dailyCheckInError = '请求太频繁，请稍后再试';
      api.dailyState = _serverDaily(signed: const <int>{});
      final container =
          containerFor(api: api, store: CheckInStore(_MemoryBox()));
      addTearDown(container.dispose);
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);

      final outcome = await container.read(checkInProvider.notifier).checkIn();
      expect(outcome.success, isFalse);
      expect(outcome.message, contains('请求太频繁'));
      expect(container.read(checkInProvider).error, contains('请求太频繁'));
    });

    test('今天已签时再点：直接提示已签，不再发请求', () async {
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = _serverDaily(signed: const <int>{21});
      final container =
          containerFor(api: api, store: CheckInStore(_MemoryBox()));
      addTearDown(container.dispose);
      expect(container.read(checkInProvider).loggedIn, isTrue);
      await pumpEventQueue(times: 4);

      final outcome = await container.read(checkInProvider.notifier).checkIn();
      expect(outcome.success, isFalse);
      expect(outcome.alreadySigned, isTrue);
      expect(api.dailyCheckInCalls, 0);
    });
  });

  group('CheckInStore（快照缓存）', () {
    test('写读往返，未知 uid 返回 null', () async {
      final store = CheckInStore(box);
      expect(store.read(4242), isNull);
      await store.save(4242, _serverDaily());
      final cached = store.read(4242);
      expect(cached?.signedDays, <int>{20, 21});
      expect(cached?.dailyId, 74);
      await store.clear(4242);
      expect(store.read(4242), isNull);
      expect(CheckInStore.keyOf(7), 'daily_7');
    });

    test('脏数据不抛异常', () async {
      final store = CheckInStore(box);
      await box.put(CheckInStore.keyOf(9), 'not-json');
      expect(store.read(9), isNull);
    });
  });

  group('签到页', () {
    Future<void> pumpPage(
      WidgetTester tester, {
      required FakeJmApi api,
      AccountSession? account = _loggedIn,
      CheckInStore? store,
      Size size = const Size(800, 600),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            checkInAccountProvider.overrideWithValue(account),
            jmBootstrapProvider.overrideWith((ref) async => api),
            checkInClockProvider.overrideWithValue(() => _today),
            // 回写余额走内存 sink：不碰真实账号 notifier（否则会触发真实网络）。
            checkInCoinSinkProvider.overrideWithValue((coin) async {}),
            checkInStoreProvider
                .overrideWithValue(store ?? CheckInStore(_MemoryBox())),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DailyCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('未登录显示登录门槛，不请求服务端', (tester) async {
      final api = FakeJmApi();
      await pumpPage(tester, api: api, account: null);

      expect(find.text('登录后才能签到'), findsOneWidget);
      expect(find.text('去登录'), findsOneWidget);
      expect(find.text('立即签到'), findsNothing);
      expect(api.dailyCalls, 0);
    });

    testWidgets('登录后渲染月历与统计，点「立即签到」后变为已签并显示 JCoin', (tester) async {
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = _serverDaily(signed: const <int>{});
      await pumpPage(tester, api: api);

      expect(find.text('2026 年 11 月'), findsOneWidget);
      expect(find.text('今日可签到'), findsOneWidget);
      expect(find.text('本月已签'), findsOneWidget);
      expect(find.text('连续天数'), findsOneWidget);
      expect(find.text('JCoin'), findsOneWidget);
      expect(find.text('150'), findsOneWidget);
      for (final label in kCheckInWeekdayLabels) {
        expect(find.text(label), findsWidgets, reason: label);
      }

      await tester.ensureVisible(find.text('立即签到'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即签到'));
      await tester.pumpAndSettle();

      expect(api.dailyCheckInPayloads.single, 'user_id=4242&daily_id=74');
      expect(find.text('今日已签到'), findsWidgets);
      expect(find.text('立即签到'), findsNothing);
      expect(find.text('今日可签到'), findsNothing);

      // 让 toast 的自动消失计时器跑完，避免残留 pending timer。
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('读取失败可重试', (tester) async {
      final api = FakeJmApi(loggedIn: true)..dailyError = '网络开小差了';
      await pumpPage(tester, api: api);

      expect(find.textContaining('读取签到记录失败'), findsOneWidget);
      expect(find.textContaining('网络开小差了'), findsOneWidget);
      expect(find.text('线路设置'), findsOneWidget, reason: '失败态要能去换线路');

      api
        ..dailyError = null
        ..dailyState = _serverDaily(signed: const <int>{})
        ..dailyToday = 21;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('今日可签到'), findsOneWidget);
      expect(api.dailyCalls, greaterThanOrEqualTo(2));
    });

    testWidgets('窄屏 320x640 不溢出', (tester) async {
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = _serverDaily(signed: const <int>{21});
      await pumpPage(tester, api: api, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('2026 年 11 月'), findsOneWidget);
      await tester.ensureVisible(find.text('今日已签到').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('入口与路由', () {
    testWidgets('「我的」入口显示登录提示，点击进入签到页（/mine/check-in）', (tester) async {
      final prefs = await testPreferences();
      final api = FakeJmApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
            downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
            jmApiProvider.overrideWithValue(api),
            jmBootstrapProvider.overrideWith((ref) async => api),
            homeRepositoryProvider.overrideWith(
              (ref) async => HomeRepository(api: api),
            ),
            checkInStoreProvider.overrideWithValue(CheckInStore(_MemoryBox())),
          ],
          child: const JmComicApp(),
        ),
      );
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final barRect = tester.getRect(find.byType(GlassNavBar));
      await tester.tapAt(
        Offset(barRect.left + barRect.width * 0.75, barRect.center.dy),
      );
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('登录后可签到领 JCoin'), findsOneWidget);

      await tester.tap(find.text('每日签到').first);
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(DailyCheckInPage), findsOneWidget);
      expect(find.text('登录后才能签到'), findsOneWidget);
      expect(api.dailyCalls, 0);
    });

    testWidgets('登录后头像那一栏显示 JCoin 余额', (tester) async {
      final prefs = await testPreferences();
      final api = FakeJmApi(loggedIn: true)..dailyToday = 21;
      api.dailyState = buildFakeDaily(signed: const <int>{20});
      const session = AccountSession(
        uid: 42,
        username: 'tester',
        state: SessionState.valid,
        coin: 320,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
            downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
            jmApiProvider.overrideWithValue(api),
            jmBootstrapProvider.overrideWith((ref) async => api),
            homeRepositoryProvider.overrideWith(
              (ref) async => HomeRepository(api: api),
            ),
            checkInStoreProvider.overrideWithValue(CheckInStore(_MemoryBox())),
            checkInCoinSinkProvider.overrideWithValue((coin) async {}),
            accountSessionProvider
                .overrideWith(() => _FakeAccountNotifier(session)),
          ],
          child: const JmComicApp(),
        ),
      );
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final barRect = tester.getRect(find.byType(GlassNavBar));
      await tester.tapAt(
        Offset(barRect.left + barRect.width * 0.75, barRect.center.dy),
      );
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // 头像那一栏的 JCoin 胶囊 + 入口摘要里的余额。
      expect(find.text('JCoin'), findsWidgets);
      expect(find.text('320'), findsOneWidget);
      expect(find.text('tester'), findsWidgets);
    });
  });
}
