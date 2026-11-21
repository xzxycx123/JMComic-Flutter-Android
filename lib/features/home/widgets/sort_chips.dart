import 'package:flutter/material.dart';

import '../../../core/constants/jm_constants.dart';
import '../../../core/icons/app_images.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';

/// 排序条：用站点自带的日榜 / 周榜 / 热门角标做视觉，对应 `/categories/filter` 的 `o` 参数。
class SortChips extends StatelessWidget {
  const SortChips({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final AlbumOrder selected;
  final ValueChanged<AlbumOrder> onSelected;

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
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: context.isLiquidGlass ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: orders.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final order = orders[index];
          final active = order == selected;
          final icon = iconFor(order);
          void select() => onSelected(order);
          final label = Text(
            order.label,
            style: AppTypography.micro.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          );
          final rank = icon == null
              ? null
              : Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Image.asset(
                    icon,
                    width: 13,
                    height: 13,
                    filterQuality: FilterQuality.medium,
                    semanticLabel: order.label,
                  ),
                );
          const padding = EdgeInsets.symmetric(horizontal: 12);
          return AppChip(
            label: label,
            leading: rank,
            onTap: select,
            selected: active,
            padding: padding,
            cornerRadius: 9,
            fillSelected: true,
            kind: AppChipKind.choice,
          );
        },
      ),
    );
  }
}
