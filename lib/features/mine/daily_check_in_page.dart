import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/check_in_store.dart';
import 'check_in_calendar.dart';
import 'check_in_providers.dart';

/// 每日签到页：本月月历 + 本月 / 累计 / 连续统计 + 「今日签到」主按钮。
///
/// 月历属于内容区域，用 solid 实色表面（[AppSurface] 默认 content kind），
/// 内部按钮也不再折射，Metal 主题下同样是实色卡片。
class DailyCheckInPage extends ConsumerStatefulWidget {
  const DailyCheckInPage({super.key});

  @override
  ConsumerState<DailyCheckInPage> createState() => _DailyCheckInPageState();
}

class _DailyCheckInPageState extends ConsumerState<DailyCheckInPage> {
  /// 当前展示的月份（每月 1 日）；为 null 时取「今天」所在月份。
  DateTime? _month;

  @override
  void initState() {
    super.initState();
    // App 常驻跨天后进来：先按当前日期刷新快照，否则「今天」还停在昨天。
    // build 期间不能改 provider 状态，放到首帧之后。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(checkInProvider.notifier).refresh();
    });
  }

  DateTime _displayedMonth(DateTime today) => _month ??= DateTime(
        today.year,
        today.month,
      );

  void _shiftMonth(int delta) {
    final current = _displayedMonth(ref.read(checkInProvider).today);
    setState(() {
      _month = DateTime(current.year, current.month + delta);
    });
  }

  Future<void> _checkIn() async {
    await ref.read(checkInProvider.notifier).checkInToday();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(checkInProvider);
    final month = _displayedMonth(state.today);
    final weeks = buildCheckInWeeks(
      month: month,
      today: state.today,
      isSigned: state.isSigned,
    );

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
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _SummaryCard(state: state),
          const SizedBox(height: 12),
          _CalendarCard(
            month: month,
            weeks: weeks,
            onPrevious: () => _shiftMonth(-1),
            onNext: () => _shiftMonth(1),
          ),
          const SizedBox(height: 14),
          AppButton(
            onPressed: state.todayChecked ? null : _checkIn,
            expanded: true,
            height: 48,
            cornerRadius: AppColors.radiusPill,
            label: state.todayChecked ? '今日已签到' : '今日签到',
            leadingIcon: IconTheme(
              data: IconThemeData(color: scheme.onPrimary),
              child: const SvgIcon(AppIcons.check, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '签到只记录在本机（日期格式 yyyy-MM-dd），不联网；同一天重复点击只算一次。',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 顶部摘要：今天状态 + 本月次数 / 累计次数 / 连续天数。
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.state});

  final CheckInState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppColors.radiusPanel);
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
                CheckInStore.dayKey(state.today),
                style: AppTypography.numeric
                    .copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              _StatCell(value: '${state.monthCount}', label: '本月次数'),
              _StatCell(value: '${state.totalCount}', label: '累计次数'),
              _StatCell(value: '${state.streak}', label: '连续天数'),
            ],
          ),
        ],
      ),
    );
  }
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

/// 月历卡：月份切换 + 周一起始表头 + 日期格子。
class _CalendarCard extends StatelessWidget {
  const _CalendarCard({
    required this.month,
    required this.weeks,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final List<List<CheckInDayCell>> weeks;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppColors.radiusPanel);
    return AppSurface(
      borderRadius: radius,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: radius,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              AppIconButton(
                tooltip: '上个月',
                icon: IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: const SvgIcon(AppIcons.back, size: 18),
                ),
                onPressed: onPrevious,
                glassTransparent: true,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
              Expanded(
                child: Text(
                  '${month.year} 年 ${month.month} 月',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.sectionTitle
                      .copyWith(color: scheme.onSurface),
                ),
              ),
              AppIconButton(
                tooltip: '下个月',
                icon: IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: const SvgIcon(AppIcons.forward, size: 18),
                ),
                onPressed: onNext,
                glassTransparent: true,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              ),
            ],
          ),
          const SizedBox(height: 6),
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

/// 单个日期格子：已签到着色 + 打勾，今天描边。
class _DayCellView extends StatelessWidget {
  const _DayCellView({required this.cell});

  final CheckInDayCell cell;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final signed = cell.signed && cell.inMonth;
    final ink = signed
        ? scheme.onPrimaryContainer
        : cell.isToday
            ? scheme.primary
            : cell.inMonth
                ? scheme.onSurface
                : scheme.onSurfaceVariant.withValues(alpha: 0.38);
    final label = '${CheckInStore.dayKey(cell.date)}'
        '${cell.isToday ? ' 今天' : ''}'
        '${signed ? ' 已签到' : ''}';
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        height: 44,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: signed ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: cell.isToday
              ? Border.all(color: scheme.primary, width: 1.4)
              : null,
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
