import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';

/// 分节头：标题 16 w700 + 「更多」+ forward 图标。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    super.key,
    this.onMore,
  });

  final String title;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.sectionTitle.copyWith(color: scheme.onSurface),
            ),
          ),
          if (onMore != null)
            AppButton.text(
              cornerRadius: 18,
              onPressed: onMore,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                textStyle: AppTypography.caption,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '更多',
                    style: AppTypography.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 2),
                  IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.forward, size: 16),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
