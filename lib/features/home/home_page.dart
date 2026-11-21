import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/jm_constants.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/home_feed.dart';
import '../../data/models/jm_category.dart';
import '../../data/models/jm_promote_module.dart';
import 'home_providers.dart';
import 'widgets/album_card.dart';
import 'widgets/category_chips.dart';
import 'widgets/feed_skeleton.dart';
import 'widgets/hero_banner.dart';
import 'widgets/section_header.dart';
import 'widgets/sort_chips.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final ScrollController _controller = ScrollController();
  bool _elevated = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    final elevated = _controller.offset > 40;
    if (elevated != _elevated) {
      setState(() => _elevated = elevated);
    }
    if (!_controller.hasClients) return;
    final remaining = _controller.position.maxScrollExtent - _controller.offset;
    if (remaining < AppConfig.loadMoreThreshold) {
      ref.read(homeFeedProvider.notifier).loadMore();
    }
  }

  void _openAlbum(String albumId) => context.push('/album/$albumId');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feedState = ref.watch(homeFeedProvider);
    final settings = ref.watch(settingsProvider);

    return AppGlassPage(
      showBackground: false,
      backgroundColor: context.isLiquidGlass ? Colors.transparent : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          edgeOffset: 56,
          onRefresh: () => ref.read(homeFeedProvider.notifier).refresh(),
          child: CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverAppBar(
                floating: true,
                pinned: false,
                elevation: 0,
                surfaceTintColor: Colors.transparent,
                backgroundColor: _elevated && !context.isLiquidGlass
                    ? scheme.surface.withValues(alpha: 0.86)
                    : Colors.transparent,
                flexibleSpace: _elevated && context.isLiquidGlass
                    ? const AppGlassChrome(child: SizedBox.expand())
                    : null,
                titleSpacing: 16,
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // 品牌标记走 img/brand 切出来的方形 mark（不是季节吉祥物）。
                    const BrandMark(asset: AppImages.brandLogo, size: 26),
                    const SizedBox(width: 8),
                    Text(
                      AppConfig.appName,
                      style: AppTypography.wordmark
                          .copyWith(color: scheme.onSurface),
                    ),
                  ],
                ),
                actions: <Widget>[
                  _AppBarAction(
                    icon: AppIcons.search,
                    tooltip: '搜索',
                    onTap: () => context.push('/search'),
                  ),
                  _AppBarAction(
                    icon: AppIcons.theme,
                    tooltip: '切换主题',
                    onTap: () {
                      final next = settings.themeMode == AppThemeMode.light
                          ? AppThemeMode.dark
                          : AppThemeMode.light;
                      ref.read(settingsProvider.notifier).setThemeMode(next);
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              ...feedState.when(
                loading: () => <Widget>[
                  const SliverFillRemaining(
                    hasScrollBody: true,
                    child: FeedSkeleton(),
                  ),
                ],
                error: (error, stackTrace) => <Widget>[
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      illustration: AppIllustrations.errorNetwork,
                      title: '线路暂时不可用',
                      description: '$error',
                      actionLabel: '重新加载',
                      onAction: () =>
                          ref.read(homeFeedProvider.notifier).refresh(),
                    ),
                  ),
                ],
                data: (feed) => _buildContent(context, feed),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, HomeFeed feed) {
    final categories = _categoriesOf(feed);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final loadingMore = ref.watch(loadingMoreProvider);
    final loadMoreError = ref.watch(loadMoreErrorProvider);

    return <Widget>[
      if (feed.fromCache && feed.updatedAt != null)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: const SvgIcon(AppIcons.refresh, size: 14),
                ),
                const SizedBox(width: 6),
                Text(
                  '上次内容 · ${_formatClock(feed.updatedAt!)} · 正在更新',
                  style: AppTypography.micro
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      if (feed.banners.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 10),
            child: HeroBanner(
              banners: feed.banners,
              onTap: (album) => _openAlbum(album.id),
            ),
          ),
        ),
      SliverPersistentHeader(
        pinned: true,
        delegate: CategoryBarDelegate(
          categories: categories,
          selectedId: selectedCategory,
          background: scheme.surface,
          divider: scheme.outlineVariant,
          onSelected: (id) {
            _controller.jumpTo(0);
            ref.read(homeFeedProvider.notifier).selectCategory(id);
          },
        ),
      ),
      if (feed.partialErrors.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Text(
              feed.partialErrors.join(' · '),
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ..._buildModules(feed.modules),
      SliverToBoxAdapter(
        child: SortChips(
          selected: ref.watch(albumOrderProvider),
          onSelected: (order) {
            _controller.jumpTo(0);
            ref.read(homeFeedProvider.notifier).selectOrder(order);
          },
        ),
      ),
      SliverToBoxAdapter(
        child: SectionHeader(
          title: selectedCategory == '0' ? '最新上架' : '分类推荐',
          onMore: () => context.push('/search'),
        ),
      ),
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
            (context, index) {
              final album = feed.grid[index];
              return AlbumCard(
                album: album,
                onTap: () => _openAlbum(album.id),
              );
            },
            childCount: feed.grid.length,
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: _GridFooter(
          loading: loadingMore,
          error: loadMoreError,
          exhausted: feed.grid.isEmpty,
          onRetry: () => ref.read(homeFeedProvider.notifier).loadMore(),
        ),
      ),
    ];
  }

  List<Widget> _buildModules(List<JmPromoteModule> modules) {
    if (modules.isEmpty) return const <Widget>[];
    final result = <Widget>[];
    for (final module in modules) {
      result.add(
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionHeader(title: module.title),
              SizedBox(
                height: 248,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: module.items.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final album = module.items[index];
                    return AlbumCard(
                      album: album,
                      layout: AlbumCardLayout.rail,
                      onTap: () => _openAlbum(album.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }
    return result;
  }

  List<JmCategory> _categoriesOf(HomeFeed feed) {
    if (feed.categories.isNotEmpty) return feed.categories;
    return JmCategoryFallback.items
        .map((item) => JmCategory(id: item.id, name: item.name))
        .toList(growable: false);
  }

  static String _formatClock(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _AppBarAction extends StatelessWidget {
  const _AppBarAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final String icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: context.isLiquidGlass
          ? AppIconButton(
              icon: SvgIcon(icon, size: 20),
              onPressed: onTap,
              tooltip: tooltip,
              color: scheme.onSurface,
            )
          : Tooltip(
              message: tooltip,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppColors.radiusPill),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: SvgIcon(icon, size: 20, color: scheme.onSurface),
                ),
              ),
            ),
    );
  }
}

class _GridFooter extends StatelessWidget {
  const _GridFooter({
    required this.loading,
    required this.error,
    required this.exhausted,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final bool exhausted;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: AppButton.text(
            onPressed: onRetry,
            leadingIcon:
                SvgIcon(AppIcons.refresh, size: 16, color: scheme.primary),
            label: '加载失败，点此重试',
          ),
        ),
      );
    }
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: AppProgressIndicator.circular(strokeWidth: 2.4),
          ),
        ),
      );
    }
    if (exhausted) return const SizedBox(height: 8);
    return const SizedBox(height: 24);
  }
}
