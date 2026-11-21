import 'package:flutter/material.dart';

import '../../../core/constants/jm_constants.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/icons/app_images.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';

/// 排序条：用站点自带的日榜 / 周榜 / 热门角标做视觉，对应 `/categories/filter` 的 `o` 参数。
///
/// 整条固定 [barHeight]（34dp），药丸高 24dp、角标图 14dp；折叠后只留当前排序
/// 与展开按钮，状态由调用方（`HomePage` 的 State）持有。
class SortChips extends StatelessWidget {
  const SortChips({
    required this.selected,
    required this.onSelected,
    super.key,
    this.collapsed = false,
    this.onToggle,
  });

  final AlbumOrder selected;
  final ValueChanged<AlbumOrder> onSelected;

  /// 折叠态：只显示当前排序 + 展开按钮。
  final bool collapsed;

  /// 折叠 / 展开回调；为 null 时不渲染切换按钮。
  final VoidCallback? onToggle;

  /// 排序条整体高度。
  static const double barHeight = 34;

  /// 榜单角标边长（图片本身 ≤ 14dp）。
  static const double rankIconSize = 14;

  static const Key toggleKey = ValueKey<String>('sort-toggle');
  static const Key collapsedLabelKey = ValueKey<String>('sort-collapsed');

  static const List<AlbumOrder> orders = <AlbumOrder>[
    AlbumOrder.latestUpdate,
    AlbumOrder.daily,
    AlbumOrder.weekly,
    AlbumOrder.monthly,
    AlbumOrder.popular,
  ];

  static String? iconFor(AlbumOrder order) => switch (order) {
        AlbumOrder.daily => AppImages.badgeDay,
        AlbumOrder.weekly => AppImages.badgeWeek,
        AlbumOrder.popular => AppImages.badgeHot,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: barHeight,
      child: Row(
        children: <Widget>[
          Expanded(
            child: collapsed ? _buildCollapsed(context) : _buildList(context),
          ),
          if (onToggle != null)
            _SortToggle(collapsed: collapsed, onTap: onToggle!),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      clipBehavior: context.isLiquidGlass ? Clip.none : Clip.hardEdge,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final order = orders[index];
        return _OrderPill(
          order: order,
          active: order == selected,
          onTap: () => onSelected(order),
        );
      },
    );
  }

  Widget _buildCollapsed(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      key: collapsedLabelKey,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Semantics(
              label: '当前排序：${selected.label}',
              child: _OrderPill(order: selected, active: true),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '已收起',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个排序药丸：高 24dp、圆角 999、solid 底（列表内容不用玻璃）。
class _OrderPill extends StatelessWidget {
  const _OrderPill({
    required this.order,
    required this.active,
    this.onTap,
  });

  final AlbumOrder order;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = SortChips.iconFor(order);
    final label = Text(
      order.label,
      style: AppTypography.micro.copyWith(
        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    final rank = icon == null
        ? null
        : Container(
            width: SortChips.rankIconSize + 2,
            height: SortChips.rankIconSize + 2,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              icon,
              width: SortChips.rankIconSize,
              height: SortChips.rankIconSize,
              filterQuality: FilterQuality.medium,
              semanticLabel: order.label,
            ),
          );
    return AppChip(
      label: label,
      leading: rank,
      onTap: onTap,
      selected: active,
      semanticLabel: '排序 ${order.label}',
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      cornerRadius: AppColors.radiusPill,
      fillSelected: true,
      kind: AppChipKind.choice,
    );
  }
}

/// 折叠 / 展开按钮：复用 forward SVG 旋转 90°（下 = 展开，上 = 收起）。
class _SortToggle extends StatelessWidget {
  const _SortToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = collapsed ? '展开排序' : '收起排序';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          key: SortChips.toggleKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
          child: SizedBox(
            width: 28,
            height: 26,
            child: Center(
              child: RotatedBox(
                quarterTurns: collapsed ? 1 : 3,
                child: SvgIcon(
                  AppIcons.forward,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
