import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/models/jm_album_detail.dart';
import '../../data/models/jm_album_summary.dart';
import '../../data/models/jm_chapter.dart';
import '../home/widgets/album_card.dart';
import '../home/widgets/cover_image.dart';
import '../home/widgets/feed_skeleton.dart';
import '../home/widgets/section_header.dart';
import '../collect/collect_providers.dart';
import 'album_providers.dart';
import 'widgets/chapter_tile.dart';
import 'widgets/comment_section.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 进入详情即清掉「有更新」角标。
    ref.listen(albumDetailProvider(albumId), (previous, next) {
      next.whenData((album) {
        ref.read(favoritesRepositoryProvider).markSeen(album.id);
      });
    });
    final detail = ref.watch(albumDetailProvider(albumId));

    return detail.when(
      loading: () => _AlbumScaffold(
        albumId: albumId,
        body: const Center(child: MascotLoading(label: '正在加载详情')),
      ),
      error: (error, stackTrace) => _AlbumScaffold(
        albumId: albumId,
        body: EmptyState(
          illustration: AppIllustrations.errorNetwork,
          title: '详情加载失败',
          description: '$error',
          actionLabel: '重试',
          onAction: () => ref.invalidate(albumDetailProvider(albumId)),
        ),
      ),
      data: (album) => _AlbumContent(album: album),
    );
  }
}

class _AlbumScaffold extends StatelessWidget {
  const _AlbumScaffold({required this.albumId, required this.body});

  final String albumId;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppGlassPage(
      appBar: AppGlassAppBar(
        leading: AppIconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'JM$albumId',
          style: AppTypography.title.copyWith(color: scheme.onSurface),
        ),
      ),
      body: body,
    );
  }
}

class _AlbumContent extends ConsumerWidget {
  const _AlbumContent({required this.album});

  final JmAlbumDetail album;

  void _openReader(BuildContext context, JmChapterRef chapter, {int page = 1}) {
    final query = <String, String>{
      'album': album.id,
      'chapter': chapter.id,
      'title': chapter.displayTitle,
      'albumTitle': album.displayTitle,
      'page': '$page',
    };
    context.push('/reader?${Uri(queryParameters: query).query}');
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    try {
      final record =
          await ref.read(downloadRepositoryProvider).enqueue(album.id);
      if (context.mounted) {
        AppToast.show(context, '已加入队列：${record.displayTitle}');
        context.go('/download');
      }
    } catch (error) {
      if (context.mounted) AppToast.show(context, '加入队列失败：$error');
    }
  }

  Future<void> _toggleFavorite(
    BuildContext context,
    WidgetRef ref,
    JmAlbumDetail album,
  ) async {
    final repository = ref.read(favoritesRepositoryProvider);
    final summary = JmAlbumSummary(
      id: album.id,
      title: album.title,
      author: album.author,
      updateAt: 0,
    );
    final added = await repository.toggle(summary);
    ref.read(favoritesItemsProvider.notifier).reload();
    if (!context.mounted) return;
    // 用自绘 toast：SnackBar 的自动消失依赖框架内部的 Timer，某些情况（无障碍模式、
    // 路由切换、弹出层）计时器根本没启动，用户看到的就是一条永远挂着的黑条。
    AppToast.show(
      context,
      added ? '已收藏' : '已取消收藏',
      actionLabel: '撤销',
      onAction: () {
        unawaited(() async {
          await repository.undo(added, summary);
          ref.read(favoritesItemsProvider.notifier).reload();
        }());
      },
    );
  }

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: 'https://18comic.vip/album/${album.id}/'),
    );
    if (!context.mounted) return;
    AppToast.show(context, '链接已复制');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final primaryChapter = album.primaryChapter;
    final progress = ref.watch(
      chapterProgressProvider(
        (albumId: album.id, chapterId: primaryChapter.id),
      ),
    );
    final isFavorite = ref.watch(favoriteIdsProvider).contains(album.id);
    final resumePage =
        progress == null || progress.page <= 1 ? 1 : progress.page;
    final ctaLabel = progress == null || progress.page <= 1
        ? '开始阅读'
        : '继续阅读 · 第 $resumePage 页';

    return AppGlassPage(
      body: Stack(
        children: <Widget>[
          CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                backgroundColor:
                    context.isLiquidGlass ? Colors.transparent : null,
                surfaceTintColor:
                    context.isLiquidGlass ? Colors.transparent : null,
                leading: AppIconButton(
                  tooltip: '返回',
                  icon: IconTheme(
                    data: IconThemeData(color: scheme.onSurface),
                    child: const SvgIcon(AppIcons.back, size: 22),
                  ),
                  onPressed: () => context.pop(),
                ),
                actions: <Widget>[
                  AppIconButton(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    selected: isFavorite,
                    color: isFavorite ? scheme.primary : scheme.onSurface,
                    icon: SvgIcon(
                      isFavorite ? AppIcons.starFilled : AppIcons.star,
                      size: 22,
                    ),
                    onPressed: () => _toggleFavorite(context, ref, album),
                  ),
                  AppIconButton(
                    tooltip: '分享',
                    color: scheme.onSurface,
                    icon: const SvgIcon(AppIcons.share, size: 20),
                    onPressed: () => _share(context),
                  ),
                  const SizedBox(width: 4),
                ],
                flexibleSpace: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    FlexibleSpaceBar(background: _CoverHeader(album: album)),
                    if (context.isLiquidGlass)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _CollapsedChrome(),
                      ),
                  ],
                ),
              ),
              SliverToBoxAdapter(child: _InfoSection(album: album)),
              SliverToBoxAdapter(child: _InteractionBar(album: album)),
              SliverToBoxAdapter(
                child:
                    SectionHeader(title: album.isSingleChapter ? '单行本' : '章节'),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final chapter = album.chapters[index];
                    final chapterProgress = ref.watch(
                      chapterProgressProvider(
                        (albumId: album.id, chapterId: chapter.id),
                      ),
                    );
                    return ChapterTile(
                      chapter: chapter,
                      index: index + 1,
                      trailingLabel: chapterProgress == null
                          ? null
                          : '读到 ${chapterProgress.page}/${chapterProgress.total}',
                      onTap: () => _openReader(
                        context,
                        chapter,
                        page: chapterProgress?.page ?? 1,
                      ),
                    );
                  },
                  childCount: album.chapters.length,
                ),
              ),
              SliverToBoxAdapter(
                child: CommentSection(
                  albumId: album.id,
                  totalHint: album.commentTotal,
                ),
              ),
              if (album.related.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(child: SectionHeader(title: '相关推荐')),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final related = album.related[index];
                        return AlbumCard(
                          album: related,
                          onTap: () => context.push('/album/${related.id}'),
                        );
                      },
                      childCount: album.related.length.clamp(0, 6).toInt(),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        ],
      ),
      bottomNavigationBar: AppGlassChrome(
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppButton(
                    height: 48,
                    onPressed: () =>
                        _openReader(context, primaryChapter, page: resumePage),
                    leadingIcon: const SvgIcon(AppIcons.play, size: 18),
                    label: ctaLabel,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 108,
                  child: AppButton.secondary(
                    height: 48,
                    onPressed: () => _download(context, ref),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SvgIcon(
                          AppIcons.download,
                          size: 18,
                          color: scheme.onSurface,
                        ),
                        const SizedBox(width: 6),
                        const Text('下载'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The expanded cover stays unfiltered; chrome appears as the toolbar pins.
class _CollapsedChrome extends StatelessWidget {
  const _CollapsedChrome();

  @override
  Widget build(BuildContext context) {
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final height = settings?.minExtent ?? kToolbarHeight;
    final opacity = settings == null
        ? 1.0
        : (1 - (settings.currentExtent - height) / 48)
            .clamp(0.0, 1.0)
            .toDouble();
    if (opacity == 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: opacity,
        child: AppGlassChrome(child: SizedBox(height: height)),
      ),
    );
  }
}

/// 点赞 / 评论两个动作条：点赞需要登录（服务端不返回计数，本地乐观 +1）。
class _InteractionBar extends ConsumerWidget {
  const _InteractionBar({required this.album});

  final JmAlbumDetail album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final like = ref.watch(albumLikeProvider(album.id));
    final comments = ref.watch(albumCommentsProvider(album.id)).valueOrNull;
    final commentCount =
        (comments?.total ?? 0) > 0 ? comments!.total : album.commentTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: <Widget>[
          _Pill(
            icon: like.liked ? AppIcons.heartFilled : AppIcons.heart,
            label: like.liked ? '已点赞 ${like.likes}' : '点赞 ${like.likes}',
            active: like.liked,
            onTap: () => _like(context, ref, like),
          ),
          const SizedBox(width: 10),
          _Pill(
            icon: AppIcons.comment,
            label: commentCount > 0 ? '评论 $commentCount' : '写评论',
            onTap: () => _comment(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _like(
    BuildContext context,
    WidgetRef ref,
    AlbumLikeState state,
  ) async {
    if (state.liked) {
      AppToast.show(context, '这本已经点过赞了');
      return;
    }
    if (!(ref.read(accountSessionProvider).valueOrNull?.isLoggedIn ?? false)) {
      await askForLogin(context);
      return;
    }
    // 前台立刻成功（notifier 在第一个 await 之前就把状态改成已赞），网络在后台跑。
    final pending = ref.read(albumLikeProvider(album.id).notifier).like();
    AppToast.show(context, '已点赞');
    final ok = await pending;
    if (!context.mounted || ok) return;
    final error = ref.read(albumLikeProvider(album.id)).error ?? '未知错误';
    AppToast.show(context, '点赞失败：$error');
  }

  Future<void> _comment(BuildContext context, WidgetRef ref) async {
    if (!(ref.read(accountSessionProvider).valueOrNull?.isLoggedIn ?? false)) {
      await askForLogin(context);
      return;
    }
    final draft = await showCommentComposer(context, albumId: album.id);
    if (draft == null || !context.mounted) return;
    sendCommentOptimistically(context, ref, albumId: album.id, draft: draft);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    final text =
        Text(label, style: AppTypography.caption.copyWith(color: foreground));
    final glyph = SvgIcon(icon, size: 16, color: foreground);
    return AppChip(
      label: text,
      leading: glyph,
      onTap: onTap,
      selected: active,
      kind: AppChipKind.action,
      foregroundColor: foreground,
      metalChild: Material(
        color: active ? scheme.primaryContainer : scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[glyph, const SizedBox(width: 6), text],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverHeader extends StatelessWidget {
  const _CoverHeader({required this.album});

  final JmAlbumDetail album;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: CoverImage(albumId: album.id, radius: 0, fit: BoxFit.cover),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0x66000000), Color(0xEE000000)],
              stops: <double>[0.0, 1.0],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              SizedBox(
                width: 96,
                height: 128,
                child: CoverImage(albumId: album.id, radius: 12),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      album.displayTitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.title.copyWith(color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      album.displayAuthor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppTypography.caption.copyWith(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.album});

  final JmAlbumDetail album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final stats = <({String label, String value})>[
      (label: '页数', value: album.totalPages > 0 ? '${album.totalPages}' : '--'),
      (label: '浏览', value: _compact(album.totalViews)),
      // `/album.likes` 是站点的「喜歡」数（点赞），收藏数在收藏夹里按本地账本算。
      (label: '喜欢', value: _compact(album.likes)),
      (label: '评论', value: _compact(album.commentTotal)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (album.tags.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: album.tags.take(12).map((tag) {
                const padding =
                    EdgeInsets.symmetric(horizontal: 10, vertical: 4);
                final label = Text(
                  tag,
                  style: AppTypography.micro
                      .copyWith(color: scheme.onSurfaceVariant),
                );
                return AppChip(
                  label: label,
                  padding: padding,
                  kind: AppChipKind.staticLabel,
                  foregroundColor: scheme.onSurfaceVariant,
                  metalChild: Container(
                    padding: padding,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(AppColors.radiusPill),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: label,
                  ),
                );
              }).toList(growable: false),
            ),
          if (album.tags.isNotEmpty) const SizedBox(height: 14),
          StatRow(items: stats),
          if (album.description.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            Text(
              album.description.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  static String _compact(int value) {
    if (value <= 0) return '--';
    if (value < 10000) return '$value';
    final wan = value / 10000;
    return '${wan.toStringAsFixed(wan >= 10 ? 0 : 1)}万';
  }
}
