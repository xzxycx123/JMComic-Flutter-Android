import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/jm_chapter.dart';

/// 章节行：第 N 话 · 标题 + forward 图标。
class ChapterTile extends StatelessWidget {
  const ChapterTile({
    required this.chapter,
    super.key,
    this.index,
    this.onTap,
    this.trailingLabel,
  });

  final JmChapterRef chapter;
  final int? index;
  final VoidCallback? onTap;
  final String? trailingLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              Container(
                width: 26,
                alignment: Alignment.centerLeft,
                child: Text(
                  '${index ?? chapter.sort}'.padLeft(2, '0'),
                  style: AppTypography.numeric.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Text(
                  chapter.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
              ),
              if (trailingLabel != null) ...<Widget>[
                Text(
                  trailingLabel!,
                  style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
              ],
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: const SvgIcon(AppIcons.forward, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 信息区统计条（页数 / 浏览 / 收藏 / 评论）。
class StatRow extends StatelessWidget {
  const StatRow({
    required this.items,
    super.key,
  });

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          for (final item in items)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.value,
                    style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
