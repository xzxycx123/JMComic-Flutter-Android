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
import '../../data/models/jm_album_detail.dart';
import '../../data/models/jm_chapter.dart';
import '../home/widgets/album_card.dart';
import '../home/widgets/cover_image.dart';
import '../home/widgets/feed_skeleton.dart';
import '../home/widgets/section_header.dart';
import 'album_providers.dart';
import 'widgets/chapter_tile.dart';

class AlbumPage extends ConsumerWidget {
  const AlbumPage({required this.albumId, super.key});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.pop(),
        ),
        title: Text('JM$albumId', style: AppTypography.title.copyWith(color: scheme.onSurface)),
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      final record = await ref.read(downloadRepositoryProvider).enqueue(album.id);
      messenger.showSnackBar(
        SnackBar(content: Text('已加入队列：${record.displayTitle}')),
      );
      if (context.mounted) context.go('/download');
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('加入队列失败：$error')));
    }
  }

  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    final added = await ref.read(favoritesProvider.notifier).toggle(album.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(added ? '已收藏' : '已取消收藏')),
    );
  }

  Future<void> _share(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: 'https://18comic.vip/album/${album.id}/'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('链接已复制')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final primaryChapter = album.primaryChapter;
    final progress = ref.watch(
      chapterProgressProvider((albumId: album.id, chapterId: primaryChapter.id)),
    );
    final isFavorite = ref.watch(favoritesProvider).contains(album.id);
    final resumePage = progress == null || progress.page <= 1 ? 1 : progress.page;
    final ctaLabel = progress == null || progress.page <= 1
        ? '开始阅读'
        : '继续阅读 · 第 $resumePage 页';

    return Scaffold(
      body: Stack(
        children: <Widget>[
          CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                pinned: true,
                expandedHeight: 260,
                leading: IconButton(
                  icon: IconTheme(
                    data: IconThemeData(color: scheme.onSurface),
                    child: const SvgIcon(AppIcons.back, size: 22),
                  ),
                  onPressed: () => context.pop(),
                ),
                actions: <Widget>[
                  IconButton(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    icon: IconTheme(
                      data: IconThemeData(
                        color: isFavorite ? scheme.primary : scheme.onSurface,
                      ),
                      child: const SvgIcon(AppIcons.bookmark, size: 20),
                    ),
                    onPressed: () => _toggleFavorite(context, ref),
                  ),
                  IconButton(
                    tooltip: '分享',
                    icon: IconTheme(
                      data: IconThemeData(color: scheme.onSurface),
                      child: const SvgIcon(AppIcons.share, size: 20),
                    ),
                    onPressed: () => _share(context),
                  ),
                  const SizedBox(width: 4),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: _CoverHeader(album: album),
                ),
              ),
              SliverToBoxAdapter(child: _InfoSection(album: album)),
              SliverToBoxAdapter(
                child: SectionHeader(title: album.isSingleChapter ? '单行本' : '章节'),
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
              if (album.related.isNotEmpty) ...<Widget>[
                const SliverToBoxAdapter(child: SectionHeader(title: '相关推荐')),
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
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton(
                  onPressed: () => _openReader(context, primaryChapter, page: resumePage),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconTheme(
                        data: IconThemeData(color: scheme.onPrimary),
                        child: const SvgIcon(AppIcons.play, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          ctaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 108,
                child: OutlinedButton(
                  onPressed: () => _download(context, ref),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      IconTheme(
                        data: IconThemeData(color: scheme.onSurface),
                        child: const SvgIcon(AppIcons.download, size: 18),
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
                      style: AppTypography.caption.copyWith(color: Colors.white70),
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
      (label: '收藏', value: _compact(album.likes)),
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
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(AppColors.radiusPill),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Text(
                    tag,
                    style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
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
              style: AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
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
