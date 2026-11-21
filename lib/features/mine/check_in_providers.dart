import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/logger.dart';
import '../../data/models/account_session.dart';
import '../../data/models/jm_daily.dart';
import '../../data/sources/jm_api_client.dart';
import '../collect/collect_providers.dart';

/// 「今天」的来源（测试可注入固定时间）。
final Provider<DateTime Function()> checkInClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// 当前账号快照（签到只关心 uid / 登录态 / JCoin）；测试里直接覆写它。
final Provider<AccountSession?> checkInAccountProvider =
    Provider<AccountSession?>(
  (ref) => ref.watch(accountSessionProvider).valueOrNull,
);

/// 把服务端下发的最新 JCoin 余额写回账号快照（「我的」头像栏读它）。
///
/// 单独抽成 provider 便于测试替换；生产实现是
/// `accountSessionProvider.notifier.updateCoin`。
final Provider<Future<void> Function(int coin)> checkInCoinSinkProvider =
    Provider<Future<void> Function(int coin)>(
  (ref) =>
      (int coin) => ref.read(accountSessionProvider.notifier).updateCoin(coin),
);

/// 签到页 / 「我的」摘要共用的快照。
///
/// 数据全部来自服务端：`GET /daily`（当月记录 + `daily_id`），签到走
/// `POST /daily_chk` 领 JCoin。本地只缓存最近一次 `/daily` 结果用于弱网回显。
class CheckInState {
  const CheckInState({
    required this.loggedIn,
    required this.userId,
    required this.today,
    this.daily,
    this.coin = 0,
    this.loading = false,
    this.error,
    this.checkingIn = false,
    this.host = '',
  });

  final bool loggedIn;
  final int userId;
  final DateTime today;
  final JmDailyState? daily;

  /// JCoin 余额（`/daily` 下发优先，否则用登录快照里的 `coin`）。
  final int coin;
  final bool loading;
  final String? error;
  final bool checkingIn;

  /// 上一次请求实际打通的接口线路（'' = 还没成功过）。
  ///
  /// 签到走的是 App 的接口线路池（www.cdn* 那批 + 域名服务下发 + 手填），
  /// 不是网页域名，所以失败时把这条线索显示出来便于换线路。
  final String host;

  bool get hasData => daily != null;

  bool get todayChecked => daily?.isSigned(today.day) ?? false;

  /// 本月已签天数（服务端记录）。
  int get monthCount => daily?.signedDays.length ?? 0;

  /// 连续签到天数：今天已签从今天往前数，否则从昨天往前数。
  ///
  /// 服务端 `/daily` 只回当月，所以连续天数最多数到本月 1 号；跨月的真实连击
  /// 需要服务端补数据，这里不臆造。
  int get streak {
    final signed = daily?.signedDays;
    if (signed == null || signed.isEmpty) return 0;
    var cursor = todayChecked ? today.day : today.day - 1;
    var count = 0;
    while (cursor >= 1 && signed.contains(cursor)) {
      count++;
      cursor--;
    }
    return count;
  }

  bool get canCheckIn =>
      loggedIn && daily != null && !todayChecked && !checkingIn;

  CheckInState copyWith({
    bool? loggedIn,
    int? userId,
    DateTime? today,
    JmDailyState? daily,
    int? coin,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? checkingIn,
    String? host,
  }) =>
      CheckInState(
        loggedIn: loggedIn ?? this.loggedIn,
        userId: userId ?? this.userId,
        today: today ?? this.today,
        daily: daily ?? this.daily,
        coin: coin ?? this.coin,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        checkingIn: checkingIn ?? this.checkingIn,
        host: host ?? this.host,
      );
}

/// 一次签到尝试的结果（页面据此弹 toast）。
class CheckInOutcome {
  const CheckInOutcome({
    required this.success,
    required this.message,
    this.alreadySigned = false,
  });

  final bool success;
  final String message;
  final bool alreadySigned;
}

final NotifierProvider<CheckInNotifier, CheckInState> checkInProvider =
    NotifierProvider<CheckInNotifier, CheckInState>(CheckInNotifier.new);

class CheckInNotifier extends Notifier<CheckInState> {
  @override
  CheckInState build() {
    // 只对「登录态 + uid」敏感：余额 / 收藏数之类的会话更新不该重拉签到记录。
    final identity = ref.watch(
      checkInAccountProvider.select(
        (account) => (account?.isLoggedIn ?? false, account?.uid ?? 0),
      ),
    );
    final loggedIn = identity.$1;
    final userId = identity.$2;
    final account = ref.read(checkInAccountProvider);
    final today = _today();
    final cached =
        loggedIn ? ref.read(checkInStoreProvider).read(userId) : null;
    final state = CheckInState(
      loggedIn: loggedIn,
      userId: userId,
      today: today,
      daily: cached,
      coin: cached?.coin ?? account?.coin ?? 0,
    );
    if (loggedIn) {
      // build 里不能直接发请求：放到微任务里，首帧照常渲染缓存。
      Future<void>.microtask(refresh);
    }
    return state;
  }

  DateTime _today() {
    final now = ref.read(checkInClockProvider)();
    return DateTime(now.year, now.month, now.day);
  }

  /// 重新拉服务端当月记录（失败保留旧数据 + error 文案）。
  ///
  /// 请求走 [JmApi] 的接口线路池（`www.cdn*` + 域名服务下发 + 手填域名），
  /// 不使用网页域名（18comic.vip 那批走网页、需要梯子，且没有 APP 接口）。
  Future<void> refresh() async {
    final current = state;
    if (!current.loggedIn) return;
    state = current.copyWith(loading: true, clearError: true);
    JmApi? api;
    try {
      final resolved = await ref.read(jmBootstrapProvider.future);
      api = resolved;
      final daily = await resolved.fetchDaily(userId: current.userId);
      await ref.read(checkInStoreProvider).save(current.userId, daily);
      state = state.copyWith(
        daily: daily,
        coin: daily.coin ?? state.coin,
        loading: false,
        clearError: true,
        host: resolved.apiHost,
      );
      final serverCoin = daily.coin;
      if (serverCoin != null) await _syncAccountCoin(serverCoin);
    } on JmApiException catch (error) {
      Log.w('签到记录拉取失败：${error.message}');
      state = state.copyWith(
        loading: false,
        error: error.message,
        host: api?.apiHost ?? state.host,
      );
    } on JmContentException catch (error) {
      Log.w('签到记录拉取失败：${error.message}');
      state = state.copyWith(
        loading: false,
        error: error.message,
        host: api?.apiHost ?? state.host,
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: '$error',
        host: api?.apiHost ?? state.host,
      );
    }
  }

  /// 服务端签到：`POST /daily_chk {user_id, daily_id}`，随后重拉 `/daily` 核对。
  ///
  /// 服务端成功时可能只回一句文案、也可能什么都不回，所以「今天 signed 变 true」
  /// 才是唯一的成功判据。
  Future<CheckInOutcome> checkIn() async {
    final daily = state.daily;
    if (!state.loggedIn || state.userId <= 0) {
      return const CheckInOutcome(success: false, message: '请先登录后再签到');
    }
    if (daily == null) {
      return const CheckInOutcome(success: false, message: '签到记录还没读到，请稍后重试');
    }
    if (state.todayChecked) {
      return const CheckInOutcome(
        success: false,
        message: '今天已经签到过了',
        alreadySigned: true,
      );
    }
    if (state.checkingIn) {
      return const CheckInOutcome(success: false, message: '正在签到，请稍候');
    }
    state = state.copyWith(checkingIn: true, clearError: true);
    var message = '';
    var alreadySigned = false;
    try {
      final api = await ref.read(jmBootstrapProvider.future);
      final result = await api.checkInDaily(
        userId: state.userId,
        dailyId: daily.dailyId,
      );
      message = result.message;
      alreadySigned = result.alreadySigned;
      // 服务端若在签到响应里直接给了新余额，先落上；refresh 之后以 /daily 为准。
      final coin = result.coin;
      if (coin != null) {
        state = state.copyWith(coin: coin);
        await _syncAccountCoin(coin);
      }
    } on JmApiException catch (error) {
      state = state.copyWith(checkingIn: false, error: error.message);
      return CheckInOutcome(success: false, message: error.message);
    } on JmContentException catch (error) {
      state = state.copyWith(checkingIn: false, error: error.message);
      return CheckInOutcome(success: false, message: error.message);
    }

    await refresh();
    final signedNow = state.daily?.isSigned(state.today.day) ?? false;
    state = state.copyWith(checkingIn: false, clearError: true);
    if (signedNow) {
      return CheckInOutcome(
        success: true,
        message: message.isEmpty ? '签到成功，JCoin 已到账' : message,
        alreadySigned: alreadySigned,
      );
    }
    return CheckInOutcome(
      success: false,
      message: message.isEmpty ? '签到没有生效，请稍后重试' : message,
      alreadySigned: alreadySigned,
    );
  }

  /// 把服务端下发的最新 JCoin 写出到账号快照（「我的」头像那一栏展示用）。
  Future<void> _syncAccountCoin(int coin) async {
    final account = ref.read(checkInAccountProvider);
    if (account == null || !account.isLoggedIn || account.coin == coin) return;
    try {
      await ref.read(checkInCoinSinkProvider)(coin);
    } catch (error) {
      Log.w('回写 JCoin 余额失败：$error');
    }
  }
}
