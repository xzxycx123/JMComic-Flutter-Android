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
import 'package:jm_comic/data/repositories/home_repository.dart';
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

/// 内存版 Box：widget 测试里 Hive 的真实文件写入跑在 fake async 下会挂住，
/// 所以签到页用内存 box，只验证 provider -> UI 的联动。
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
  bool get isEmpty => _data.isEmpty;

  @override
  bool get isNotEmpty => _data.isNotEmpty;

  @override
  int get length => _data.length;
}

/// 工单四：每日签到与月历。
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

  CheckInStore storeAt(DateTime today) => CheckInStore(box, clock: () => today);

  group('CheckInStore 持久化', () {
    test('同一天重复签到幂等：只落一条 yyyy-MM-dd 记录', () async {
      final store = storeAt(DateTime(2026, 2, 1, 9, 30));

      expect(await store.checkIn(DateTime(2026, 2, 1)), isTrue);
      expect(await store.checkIn(DateTime(2026, 2, 1, 23, 59)), isFalse);
      expect(await store.checkIn(DateTime(2026, 2, 1, 0, 1)), isFalse);

      expect(box.length, 1);
      expect(box.containsKey('2026-02-01'), isTrue);
      expect(store.totalCount(), 1);
      expect(store.isSigned(DateTime(2026, 2, 1)), isTrue);
    });

    test('未来日期拒绝签到，且不写盘', () async {
      final store = storeAt(DateTime(2026, 2, 1, 10));

      expect(await store.checkIn(DateTime(2026, 2, 2)), isFalse);
      expect(await store.checkIn(DateTime(2026, 3, 1)), isFalse);
      expect(box.isEmpty, isTrue);

      // 昨天 / 今天都可以写（历史只读由 UI 保证，存储层保留补录能力）。
      expect(await store.checkIn(DateTime(2026, 1, 31)), isTrue);
      expect(await store.checkIn(DateTime(2026, 2, 1)), isTrue);
      expect(box.length, 2);
    });

    test('日期键格式为 yyyy-MM-dd，脏键不参与统计', () async {
      final store = storeAt(DateTime(2026, 11, 21));
      await store.checkIn(DateTime(2026, 9, 5));
      expect(store.signedKeys(), <String>{'2026-09-05'});
      expect(CheckInStore.dayKey(DateTime(2026, 1, 2)), '2026-01-02');

      await box.put('not-a-date', true);
      await box.put('2026-13-01', true);
      expect(store.totalCount(), 1);
      expect(store.signedDays(), <DateTime>[DateTime(2026, 9, 5)]);
    });
  });

  group('连续天数', () {
    test('今天已签：从今天向前算，覆盖跨月', () async {
      final store = storeAt(DateTime(2026, 2, 1, 10));
      await store.checkIn(DateTime(2026, 1, 30));
      await store.checkIn(DateTime(2026, 1, 31));
      await store.checkIn(DateTime(2026, 2, 1));

      final state =
          CheckInState(signedKeys: store.signedKeys(), today: store.today);
      expect(state.todayChecked, isTrue);
      expect(state.streak, 3);
      expect(state.monthCount, 1);
      expect(state.totalCount, 3);
    });

    test('今天未签：从昨天向前算，覆盖跨年', () async {
      final store = storeAt(DateTime(2027, 1, 1, 8));
      await store.checkIn(DateTime(2026, 12, 30));
      await store.checkIn(DateTime(2026, 12, 31));

      final state =
          CheckInState(signedKeys: store.signedKeys(), today: store.today);
      expect(state.todayChecked, isFalse);
      expect(state.streak, 2);
      expect(state.monthCount, 0);
    });

    test('断签归零：昨天与前天都不连续时连续天数为 0', () async {
      final store = storeAt(DateTime(2026, 2, 10));
      await store.checkIn(DateTime(2026, 2, 5));
      await store.checkIn(DateTime(2026, 2, 6));

      final state =
          CheckInState(signedKeys: store.signedKeys(), today: store.today);
      expect(state.streak, 0);
      expect(state.totalCount, 2);
    });
  });

  group('月历生成', () {
    test('周一起始、按周分组、只统计本月天数、今天标记', () {
      final today = DateTime(2026, 11, 21);
      const signedDay = '2026-11-20';
      final weeks = buildCheckInWeeks(
        month: DateTime(2026, 11),
        today: today,
        isSigned: (day) => CheckInStore.dayKey(day) == signedDay,
      );
      final cells = weeks.expand((week) => week).toList();

      expect(weeks, isNotEmpty);
      expect(weeks.every((week) => week.length == 7), isTrue);
      // 首格一定是周一（2026-11-01 是周日，所以要补 6 天到 10-26 周一）。
      expect(weeks.first.first.date.weekday, DateTime.monday);
      expect(weeks.first.first.date, DateTime(2026, 10, 26));
      expect(cells.where((cell) => cell.inMonth).length, 30);
      expect(cells.length, weeks.length * 7);
      expect(cells.where((cell) => cell.isToday).single.date, today);
      expect(cells.where((cell) => cell.isToday).single.inMonth, isTrue);
      expect(
        cells.where((cell) => cell.signed).single.date,
        DateTime(2026, 11, 20),
      );
    });

    test('2 月与闰年 2 月的天数正确', () {
      final feb2026 = buildCheckInWeeks(
        month: DateTime(2026, 2),
        today: DateTime(2026, 2, 1),
        isSigned: (_) => false,
      ).expand((week) => week).toList();
      expect(feb2026.where((cell) => cell.inMonth).length, 28);

      final feb2028 = buildCheckInWeeks(
        month: DateTime(2028, 2),
        today: DateTime(2028, 2, 1),
        isSigned: (_) => false,
      ).expand((week) => week).toList();
      expect(feb2028.where((cell) => cell.inMonth).length, 29);
    });
  });

  group('provider 刷新', () {
    test('签到后状态立即更新（我的摘要与签到页共用同一状态）', () async {
      final store = storeAt(DateTime(2026, 11, 21, 10));
      await store.checkIn(DateTime(2026, 11, 20));
      final container = ProviderContainer(
        overrides: <Override>[checkInStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(container.read(checkInProvider).todayChecked, isFalse);
      expect(container.read(checkInProvider).streak, 1);

      // 「我的」与签到页都 watch 同一个 provider：签到必须触发一次通知（重建）。
      var notifications = 0;
      container.listen<CheckInState>(checkInProvider, (previous, next) {
        if (previous?.todayChecked != next.todayChecked) notifications++;
      });

      expect(
        await container.read(checkInProvider.notifier).checkInToday(),
        isTrue,
      );
      final state = container.read(checkInProvider);
      expect(state.todayChecked, isTrue);
      expect(state.streak, 2);
      expect(state.totalCount, 2);
      expect(state.monthCount, 2);
      expect(notifications, 1);

      // 重复签到：不再新增，状态不变。
      expect(
        await container.read(checkInProvider.notifier).checkInToday(),
        isFalse,
      );
      expect(container.read(checkInProvider).totalCount, 2);
      expect(notifications, 1);
    });
  });

  group('签到页', () {
    testWidgets('展示月历与统计，点击后按钮与打勾更新，未来/历史格子不可签', (tester) async {
      final memory = _MemoryBox();
      final store =
          CheckInStore(memory, clock: () => DateTime(2026, 11, 21, 10));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[checkInStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DailyCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('2026 年 11 月'), findsOneWidget);
      expect(find.text('今日可签到'), findsOneWidget);
      for (final label in kCheckInWeekdayLabels) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('连续天数'), findsOneWidget);

      // 历史日期格不可点击：点过去不留记录。
      await tester.tap(find.text('15'));
      await tester.pump();
      expect(memory.isEmpty, isTrue);

      // 主按钮在 800x600 下需滚动到可见区域再点。
      await tester.ensureVisible(find.text('今日签到'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('今日签到'));
      await tester.pumpAndSettle();

      expect(memory.containsKey('2026-11-21'), isTrue);
      expect(find.text('今日已签到'), findsWidgets);
      expect(find.text('今日可签到'), findsNothing);
      // 今天格子打勾（SvgIcon 复用 AppIcons.check）。
      expect(find.text('21'), findsOneWidget);

      // 再来一次仍幂等（按钮已置灰，点不动）。
      await tester.tap(find.text('今日已签到').last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(memory.length, 1);
    });

    testWidgets('上月 / 下月切换', (tester) async {
      final memory = _MemoryBox();
      final store =
          CheckInStore(memory, clock: () => DateTime(2026, 11, 21, 10));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[checkInStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DailyCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('上个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 10 月'), findsOneWidget);
      expect(find.text('今日签到'), findsOneWidget);

      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('下个月'));
      await tester.pumpAndSettle();
      expect(find.text('2026 年 12 月'), findsOneWidget);
      expect(memory.isEmpty, isTrue);
    });

    testWidgets('窄屏 320x640 不溢出（今天 + 已签到同格）', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final memory = _MemoryBox();
      final store =
          CheckInStore(memory, clock: () => DateTime(2026, 11, 21, 10));
      await store.checkIn(DateTime(2026, 11, 21));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[checkInStoreProvider.overrideWithValue(store)],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const DailyCheckInPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('2026 年 11 月'), findsOneWidget);
      expect(find.text('今日已签到'), findsWidgets);
      await tester.ensureVisible(find.text('今日已签到').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('端到端（我的 -> 签到页 -> 我的）', () {
    testWidgets('入口摘要显示状态，签到后返回「我的」立即更新', (tester) async {
      final prefs = await testPreferences();
      final memory = _MemoryBox();
      final store =
          CheckInStore(memory, clock: () => DateTime(2026, 11, 21, 10));
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            settingsStoreProvider.overrideWith((_) => _MemorySettingsStore()),
            downloadHistoryProvider.overrideWithValue(MemoryDownloadHistory()),
            jmApiProvider.overrideWithValue(FakeJmApi()),
            jmBootstrapProvider.overrideWith((ref) async => FakeJmApi()),
            homeRepositoryProvider.overrideWith(
              (ref) async => HomeRepository(api: FakeJmApi()),
            ),
            checkInStoreProvider.overrideWithValue(store),
          ],
          child: const JmComicApp(),
        ),
      );
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // 切到「我的」。
      final barRect = tester.getRect(find.byType(GlassNavBar));
      await tester.tapAt(
        Offset(barRect.left + barRect.width * 0.75, barRect.center.dy),
      );
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('今日可签到 · 连续 0 天'), findsOneWidget);

      // 进签到页。
      await tester.tap(find.text('每日签到').first);
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byType(DailyCheckInPage), findsOneWidget);
      expect(find.text('连续天数'), findsOneWidget);

      // 签到。
      await tester.ensureVisible(find.text('今日签到'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('今日签到'));
      for (var index = 0; index < 8; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(memory.containsKey('2026-11-21'), isTrue);

      // 返回「我的」：摘要立即更新（同一个 provider，无需重新进入 tab）。
      await tester.tap(find.byTooltip('返回'));
      for (var index = 0; index < 12; index++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('今日已签到 · 连续 1 天'), findsOneWidget);
    });
  });
}
