import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/jm_category.dart';

/// 粘性分类条：高 44，chip 高 32、圆角 999、选中 primary 实底。
class CategoryChips extends StatelessWidget {
  const CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<JmCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedId;
          return GestureDetector(
            onTap: () => onSelected(category.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? scheme.primary : scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppColors.radiusPill),
                border: Border.all(
                  color: selected ? Colors.transparent : scheme.outline,
                ),
              ),
              child: Text(
                category.name,
                style: AppTypography.caption.copyWith(
                  color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 粘性头部代理（SliverPersistentHeader pinned）。
class CategoryBarDelegate extends SliverPersistentHeaderDelegate {
  const CategoryBarDelegate({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.background,
    required this.divider,
  });

  final List<JmCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final Color background;
  final Color divider;

  @override
  double get minExtent => 44;

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.94),
        border: Border(bottom: BorderSide(color: divider, width: 0.5)),
      ),
      child: CategoryChips(
        categories: categories,
        selectedId: selectedId,
        onSelected: onSelected,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CategoryBarDelegate oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.categories.length != categories.length ||
      oldDelegate.background != background;
}
