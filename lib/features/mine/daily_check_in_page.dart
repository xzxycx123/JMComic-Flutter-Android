import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/models/jm_daily.dart';
import 'check_in_calendar.dart';
import 'check_in_providers.dart';

/// 每日签到（服务端）：登录后 `GET /daily` 读当月记录，`POST /daily_chk` 签到领
/// JCoin。月历属内容区域，用 solid 实色表面，材质切到 Metal 也一样。
class DailyCheckInPage extends ConsumerWidget {
  const DailyCheckInPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(checkInProvider);

    return AppGlassPage(
      appBar: AppGlassAppBar(
        leading: AppIconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text('每日签到'),
        actions: <Widget>[
          if (state.loggedIn)
            AppIconButton(
              tooltip: '刷新',
              icon: IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: const SvgIcon(AppIcons.refresh, size: 20),
              ),
              onPressed: state.loading
                  ? null
                  : () => ref.read(checkInProvider.notifier).refresh(),
              glassTransparent: true,
            ),
        ],
      ),
      body: state.loggedIn ? _Body(state: state) : const _LoginGate(),
    );
  }
}

/// 未登录：签到必须走服务端账号，这里只留登录入口。
class _LoginGate extends StatelessWidget {
  const _LoginGate();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppColors.radiusPanel);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        AppSurface(
          borderRadius: radius,
          padding: const EdgeInsets.all(18),
          metalDecoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: radius,
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.user, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '登录后才能签到',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.sectionTitle
                          .copyWith(color: scheme.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '签到由服务端记账：每天签到一次可领 JCoin，签到记录跟着账号走，换设备也能看到。',
                style:
                    AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              AppButton(
                onPressed: () => context.push('/login'),
                expanded: true,
                height: 48,
                cornerRadius: AppColors.radiusPill,
                label: '去登录',
                leadingIcon: IconTheme(
                  data: IconThemeData(color: scheme.onPrimary),
                  child: const SvgIcon(AppIcons.user, size: 18),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (!state.hasData && state.loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!state.hasData) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: <Widget>[
          Text(
            state.error == null ? '还没有拿到签到记录' : '读取签到记录失败：${state.error}',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (state.host.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '当前线路：${state.host}',
              textAlign: TextAlign.center,
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            '签到走 App 的接口线路（www.cdn* / 域名服务下发 / 手填域名），不是网页域名；'
            '连不上时换一条线路或手动填一个能直连的域名，再回来点重试。',
            textAlign: TextAlign.center,
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              AppButton.secondary(
                onPressed: () => ref.read(checkInProvider.notifier).refresh(),
                cornerRadius: AppColors.radiusPill,
                label: '重试',
              ),
              const SizedBox(width: 10),
              AppButton.text(
                onPressed: () => context.push('/mine/settings'),
                cornerRadius: AppColors.radiusPill,
                label: '线路设置',
              ),
            ],
          ),
        ],
      );
    }

    final daily = state.daily!;
    final weeks = buildCheckInWeeks(
      month: state.today,
      today: state.today,
      daily: daily,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: <Widget>[
        _SummaryCard(state: state),
        const SizedBox(height: 12),
        _CalendarCard(month: state.today, weeks: weeks),
        const SizedBox(height: 14),
        AppButton(
          onPressed: state.canCheckIn ? () => _checkIn(context, ref) : null,
          loading: state.checkingIn,
          expanded: true,
          height: 48,
          cornerRadius: AppColors.radiusPill,
          label: state.todayChecked ? '今日已签到' : '立即签到',
          leadingIcon: IconTheme(
            data: IconThemeData(
              color:
                  state.canCheckIn ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            child: const SvgIcon(AppIcons.check, size: 18),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _noteOf(daily, state.host),
          style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (state.error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            '刷新失败：${state.error}',
            style: AppTypography.micro.copyWith(color: scheme.error),
          ),
        ],
      ],
    );
  }

  Future<void> _checkIn(BuildContext context, WidgetRef ref) async {
    final outcome = await ref.read(checkInProvider.notifier).checkIn();
    if (!context.mounted) return;
    AppToast.show(
      context,
      outcome.message,
      duration: Duration(seconds: outcome.success ? 3 : 4),
    );
  }

  static String _noteOf(JmDailyState daily, String host) {
    final buffer = StringBuffer(
      '签到由服务端记账并发放 JCoin，JCoin 显示服务端最近一次下发的余额；'
      '本机只缓存最近一次记录，可离线查看。',
    );
    if (daily.makeupLimit > 0) {
      buffer.write(
        ' 本月补签 ${daily.makeupUsed}/${daily.makeupLimit}'
        '（补签需看广告，App 内暂未接入）。',
      );
    }
    if (host.isNotEmpty) buffer.write(' 当前线路 $host。');
    return buffer.toString();
  }
}

/// 顶部摘要：本月已签 / 连续天数 / JCoin 余额。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppColors.radiusPanel);
    final daily = state.daily;
    return AppSurface(
      borderRadius: radius,
      padding: const EdgeInsets.all(16),
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconTheme(
                data: IconThemeData(
                  color: state.todayChecked
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                child: const SvgIcon(AppIcons.check, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  state.todayChecked ? '今日已签到' : '今日可签到',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sectionTitle
                      .copyWith(color: scheme.onSurface),
                ),
              ),
              Text(
                '${state.today.year}-${_two(state.today.month)}-${_two(state.today.day)}',
                style: AppTypography.numeric
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (daily != null && daily.eventName.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              '${daily.eventName}'
              '${daily.currentProgress.isEmpty ? '' : ' · ${daily.currentProgress}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _StatCell(value: '${state.monthCount}', label: '本月已签'),
              _StatCell(value: '${state.streak}', label: '连续天数'),
              _StatCell(value: '${state.coin}', label: 'JCoin'),
            ],
          ),
        ],
      ),
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.title.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 月历卡：月份标题 + 周一起始表头 + 日期格子。
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({required this.month, required this.weeks});

  final DateTime month;
  final List<List<CheckInDayCell>> weeks;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppColors.radiusPanel);
    return AppSurface(
      borderRadius: radius,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Text(
            '${month.year} 年 ${month.month} 月',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.sectionTitle.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final label in kCheckInWeekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      maxLines: 1,
                      style: AppTypography.micro
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (final week in weeks)
            Row(
              children: <Widget>[
                for (final cell in week)
                  Expanded(child: _DayCellView(cell: cell)),
              ],
            ),
        ],
      ),
    );
  }
}

/// 单个日期格子：已签到着色 + 打勾，奖励日加描边，今天高亮。
class _DayCellView extends StatelessWidget {
  const _DayCellView({required this.cell});

  final CheckInDayCell cell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signed = cell.signed;
    final ink = signed
        ? scheme.onPrimaryContainer
        : cell.isToday
            ? scheme.primary
            : cell.inMonth
                ? (cell.future
                    ? scheme.onSurfaceVariant.withValues(alpha: 0.75)
                    : scheme.onSurface)
                : scheme.onSurfaceVariant.withValues(alpha: 0.38);
    final border = cell.isToday
        ? Border.all(color: scheme.primary, width: 1.4)
        : cell.bonus && cell.inMonth
            ? Border.all(color: scheme.outline, width: 1)
            : null;
    final label =
        '${cell.date.year}-${cell.date.month.toString().padLeft(2, '0')}'
        '-${cell.date.day.toString().padLeft(2, '0')}'
        '${cell.isToday ? ' 今天' : ''}'
        '${signed ? ' 已签到' : ''}'
        '${cell.bonus ? ' 奖励日' : ''}';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: signed ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: border,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${cell.date.day}',
              maxLines: 1,
              style: AppTypography.caption.copyWith(color: ink),
            ),
            SizedBox(
              height: 11,
              child: signed
                  ? IconTheme(
                      data: IconThemeData(color: ink),
                      child: const SvgIcon(AppIcons.check, size: 10),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
