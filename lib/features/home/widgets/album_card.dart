import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
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
    this.caption,
    this.onTap,
    this.onLongPress,
  });

  final JmAlbumSummary album;
  final AlbumCardLayout layout;
  final Widget? caption;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final isRail = layout == AlbumCardLayout.rail;
    // 标签来自模型的 displayTags（已过滤空值 / N/A / 超长 / 重复，最多 2 个）。
    //
    // 调用方自带 caption（搜索结果卡在自己那行渲染标签 chips）时，封面不再重复
    // 渲染同一批标签，避免同一张卡上出现两份相同文案。
    final tags = caption == null ? album.displayTags : const <String>[];
    final cover = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CoverImage(albumId: album.id),
        if (tags.isNotEmpty)
          Positioned(
            left: 8,
            top: 8,
            right: album.isNew ? 40 : 8,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (var index = 0; index < tags.length; index++) ...<Widget>[
                  if (index > 0) const SizedBox(width: 4),
                  Flexible(child: _CoverTag(text: tags[index])),
                ],
              ],
            ),
          ),
        Positioned(
          left: 8,
          bottom: 8,
          child: _CoverLikes(album: album),
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
            // 滚动内容里的标题底衬用实色，不用玻璃（避免折射层套在列表里）。
            if (context.isLiquidGlass)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            caption ?? _CardCaption(album: album),
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

/// 封面左上角标签：实色药丸（列表内容不用玻璃），最多 2 个、单行省略。
class _CoverTag extends StatelessWidget {
  const _CoverTag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.micro.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 封面左下角喜欢数：心形 SVG + 数字（无计数统一 `--`）。
class _CoverLikes extends StatelessWidget {
  const _CoverLikes({required this.album});

  final JmAlbumSummary album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCount = album.displayLikes != JmAlbumSummary.noLikeCount;
    final ink = album.liked ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      label: hasCount ? '喜欢 ${album.likes}' : '暂无喜欢数',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SvgIcon(
                album.liked ? AppIcons.heartFilled : AppIcons.heart,
                size: 11,
                color: ink,
              ),
              const SizedBox(width: 3),
              Text(
                album.displayLikes,
                maxLines: 1,
                style: AppTypography.micro.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
