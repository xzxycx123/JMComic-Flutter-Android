import 'package:flutter/material.dart';

import '../../../core/icons/app_images.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../core/utils/logger.dart';
import '../../../data/models/jm_album_summary.dart';
import 'cover_image.dart';

enum AlbumCardLayout {
  /// 双列瀑布流（首页 / 搜索结果）。
  grid,

  /// 横滑分节（固定宽 148）。
  rail,
}

/// 本子卡片：封面 + 2 行标题 + 作者/分类。
class AlbumCard extends StatelessWidget {
  const AlbumCard({
    required this.album,
    super.key,
    this.layout = AlbumCardLayout.grid,
    this.onTap,
    this.onLongPress,
  });

  final JmAlbumSummary album;
  final AlbumCardLayout layout;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isRail = layout == AlbumCardLayout.rail;
    final cover = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CoverImage(albumId: album.id),
        if (album.categoryTitle.isNotEmpty)
          Positioned(
            left: 8,
            top: 8,
            child: _CategoryBadge(text: album.categoryTitle),
          ),
        if (album.isNew)
          Positioned(
            right: 6,
            top: 6,
            child: Image.asset(
              AppImages.badgeNew,
              width: 30,
              filterQuality: FilterQuality.medium,
              semanticLabel: '新上架',
            ),
          ),
      ],
    );
    final card = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: isRail ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        // 横滑分节有固定高度：封面吃剩余空间，避免大字号时 Column 溢出。
        if (isRail)
          Expanded(child: cover)
        else
          AspectRatio(aspectRatio: 3 / 4, child: cover),
        const SizedBox(height: 8),
        Stack(
          children: <Widget>[
            if (context.isLiquidGlass)
              Positioned.fill(
                child: IgnorePointer(
                  child: AppSurface(
                    kind: AppSurfaceKind.controlGroup,
                    borderRadius: BorderRadius.circular(6),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            _CardCaption(album: album),
          ],
        ),
      ],
    );

    return SizedBox(
      width: isRail ? 148 : null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Log.d('打开车号 ${album.id}');
            onTap?.call();
          },
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          child: card,
        ),
      ),
    );
  }
}

class _CardCaption extends StatelessWidget {
  const _CardCaption({required this.album});

  final JmAlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          album.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.cardTitle.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 2),
        Text(
          album.displayAuthor,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CategoryBadge extends StatelessWidget {
  const _CategoryBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
    );
    return AppBadge(
      label: label,
      metalChild: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
        ),
        child: label,
      ),
    );
  }
}
