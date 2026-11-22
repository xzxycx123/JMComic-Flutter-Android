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

/// 双列网格卡片的宽高比：正文是「2 行标题 + 作者 + 标签行」，字号越大正文越高，
/// 卡片按比例放宽（scale = 1 时仍是 0.52），避免正文把封面挤出溢出。
double albumGridAspectRatio(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  final extra = (scale - 1).clamp(0.0, 1.0);
  return 0.52 / (1 + 0.3 * extra);
}

/// 本子卡片：封面（左上角分类）+ 2 行标题 + 作者 + 作品标签。
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
    final cover = Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CoverImage(albumId: album.id),
        // 左上角：分类名（`同人` / `單本` …）。作品标签不在这里，画在作者名下面。
        if (album.cardCategory != null)
          Positioned(
            left: 6,
            top: 6,
            right: album.isNew ? 42 : 6,
            child: _CoverCategory(label: album.cardCategory!),
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
        // 标题/作者/标签直接铺在页面上：LiquidGlass 模式下不再垫圆角矩形底衬。
        caption ?? _CardCaption(album: album),
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
        // 作品标签放在作者名下面；药丸按内容宽度排版，不截断、不出省略号。
        if (album.cardTags.isNotEmpty) ...<Widget>[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: <Widget>[
              for (final tag in album.cardTags)
                AppChip(
                  label: Text(
                    tag,
                    style: AppTypography.micro
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
                  cornerRadius: 5,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 封面左上角的分类药丸（`同人` / `單本` / `English Manga` …），单行不截断。
class _CoverCategory extends StatelessWidget {
  const _CoverCategory({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: AppTypography.micro.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
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
