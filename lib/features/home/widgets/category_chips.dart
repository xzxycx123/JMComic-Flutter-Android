import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/jm_category.dart';

/// 粘性分类条：高 44，chip 高约 27、圆角 999（药丸）、solid 实底，选中 primary 实底。
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

  /// 分类条高度（与 [CategoryBarDelegate] 的 extent 一致）。
  static const double barHeight = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: barHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: context.isLiquidGlass ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = categories[index];
          final selected = category.id == selectedId;
          final label = Text(
            category.name,
            style: AppTypography.caption.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          );
          const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 5);
          void select() => onSelected(category.id);
          return AppChip(
            label: label,
            selected: selected,
            onTap: select,
            kind: AppChipKind.choice,
            semanticLabel: category.name,
            cornerRadius: AppColors.radiusPill,
            fillSelected: true,
            padding: padding,
          );
        },
      ),
    );
  }
}

/// 二级分类条：只有带 `sub_categories` 的分类（同人 / 單本 / 短篇 …）才显示。
///
/// 点击后按 `c=父slug_子slug` 重新筛选；「全部」对应空串（只按一级分类）。
class SubCategoryChips extends StatelessWidget {
  const SubCategoryChips({
    required this.subs,
    required this.selectedSlug,
    required this.onSelected,
    super.key,
  });

  final List<JmSubCategory> subs;
  final String selectedSlug;
  final ValueChanged<String> onSelected;

  static const double barHeight = 38;

  @override
  Widget build(BuildContext context) {
    final entries = <({String slug, String label})>[
      (slug: '', label: '全部'),
      ...subs
          .where((sub) => sub.slug.isNotEmpty && sub.name.isNotEmpty)
          .map((sub) => (slug: sub.slug, label: sub.name)),
    ];
    if (entries.length <= 1) return const SizedBox.shrink();
    return SizedBox(
      height: barHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: context.isLiquidGlass ? Clip.none : Clip.hardEdge,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        itemCount: entries.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final selected = entry.slug == selectedSlug;
          return AppChip(
            label: Text(
              entry.label,
              style: AppTypography.micro.copyWith(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: selected,
            onTap: () => onSelected(entry.slug),
            kind: AppChipKind.choice,
            semanticLabel: '二级分类 ${entry.label}',
            cornerRadius: AppColors.radiusPill,
            fillSelected: true,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
  double get minExtent => CategoryChips.barHeight;

  @override
  double get maxExtent => CategoryChips.barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return AppGlassChrome(
      metalColor: background.withValues(alpha: 0.94),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: divider, width: 0.5)),
        ),
        child: CategoryChips(
          categories: categories,
          selectedId: selectedId,
          onSelected: onSelected,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant CategoryBarDelegate oldDelegate) =>
      oldDelegate.selectedId != selectedId ||
      oldDelegate.categories.length != categories.length ||
      oldDelegate.background != background;
}
