import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/jm_album_summary.dart';
import '../../home/widgets/album_card.dart';

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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.52,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => AlbumCard(
                  album: items[index],
                  onTap: () => onTap(items[index]),
                ),
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
