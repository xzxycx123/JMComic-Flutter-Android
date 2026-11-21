import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show SliverConstraints, SliverGridLayout;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/jm_album_summary.dart';
import '../../home/widgets/album_card.dart';
import '../search_providers.dart';

/// 搜索结果网格：双列，触底自动加载下一页。
class ResultGrid extends StatelessWidget {
  const ResultGrid({
    required this.items,
    required this.onTap,
    super.key,
    this.onLoadMore,
    this.loadingMore = false,
    this.error,
    this.onRetry,
  });

  final List<JmAlbumSummary> items;
  final ValueChanged<JmAlbumSummary> onTap;
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final String? error;
  final VoidCallback? onRetry;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final remaining =
        notification.metrics.maxScrollExtent - notification.metrics.pixels;
    if (remaining < AppConfig.loadMoreThreshold) {
      onLoadMore?.call();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: _SearchGridDelegate(
                captionHeight:
                    MediaQuery.textScalerOf(context).scale(13) * 2.64 +
                        MediaQuery.textScalerOf(context).scale(11) * 2.7 +
                        22,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final album = items[index];
                  return AlbumCard(
                    key: ValueKey(album.id),
                    album: album,
                    caption: _SearchCaption(album: album),
                    onTap: () => onTap(album),
                  );
                },
                childCount: items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: loadingMore
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: AppProgressIndicator.circular(strokeWidth: 2.4),
                      )
                    : error != null
                        ? AppButton.text(
                            onPressed: onRetry,
                            leadingIcon: SvgIcon(
                              AppIcons.refresh,
                              size: 16,
                              color: scheme.primary,
                            ),
                            label: '加载失败，点此重试',
                          )
                        : const SizedBox(height: 8),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}

class _SearchGridDelegate extends SliverGridDelegateWithFixedCrossAxisCount {
  const _SearchGridDelegate({required this.captionHeight})
      : super(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 16);

  final double captionHeight;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = (constraints.crossAxisExtent - crossAxisSpacing) / 2;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: crossAxisCount,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      mainAxisExtent: width.clamp(0.0, double.infinity) * 4 / 3 + captionHeight,
    ).getLayout(constraints);
  }

  @override
  bool shouldRelayout(covariant _SearchGridDelegate oldDelegate) =>
      captionHeight != oldDelegate.captionHeight;
}

class _SearchCaption extends ConsumerWidget {
  const _SearchCaption({required this.album});

  final JmAlbumSummary album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final metadata = album.tags.isEmpty || !album.hasKnownAuthor
        ? ref.watch(searchAlbumMetadataProvider(album.id)).valueOrNull
        : null;
    final detailAuthor = metadata?.author.trim();
    final author = !album.hasKnownAuthor &&
            detailAuthor != null &&
            detailAuthor.isNotEmpty &&
            detailAuthor.toUpperCase() != 'N/A'
        ? detailAuthor
        : album.displayAuthor;
    final tags =
        album.tags.isNotEmpty ? album.tags : metadata?.tags ?? const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          album.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.cardTitle.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 2),
        Text(
          author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              for (final tag in tags.take(3)) ...[
                if (tag != tags.first) const SizedBox(width: 4),
                Flexible(
                  child: AppChip(
                    label: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.micro
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    cornerRadius: 5,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// 结果头：`共 N 条 · “关键词”`（右侧留视图切换位）。
class ResultHeader extends StatelessWidget {
  const ResultHeader({
    required this.total,
    required this.keyword,
    super.key,
    this.trailing,
  });

  final int total;
  final String keyword;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: context.isLiquidGlass
                ? Row(
                    children: <Widget>[
                      AppBadge(
                        label: Text('共 $total 条', style: AppTypography.caption),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '“$keyword”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  )
                : Text(
                    '共 $total 条 · “$keyword”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption
                        .copyWith(color: scheme.onSurfaceVariant),
                  ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
