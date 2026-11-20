import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/local/progress_store.dart';
import '../home/widgets/cover_image.dart';
import '../home/widgets/feed_skeleton.dart';

/// 阅读历史：`progress:{albumId}:{chapterId}` 的账本视图，按最近阅读倒序。
final NotifierProvider<ReadingHistoryNotifier, List<ReadingHistoryEntry>>
    readingHistoryProvider =
    NotifierProvider<ReadingHistoryNotifier, List<ReadingHistoryEntry>>(
  ReadingHistoryNotifier.new,
);

class ReadingHistoryNotifier extends Notifier<List<ReadingHistoryEntry>> {
  @override
  List<ReadingHistoryEntry> build() => ref.watch(progressStoreProvider).entries();

  void reload() => state = ref.read(progressStoreProvider).entries();

  Future<void> remove(ReadingHistoryEntry entry) async {
    await ref
        .read(progressStoreProvider)
        .remove(entry.albumId, entry.chapterId);
    reload();
  }

  Future<void> clear() async {
    await ref.read(progressStoreProvider).clear();
    reload();
  }
}

class ReadHistoryPage extends ConsumerStatefulWidget {
  const ReadHistoryPage({super.key});

  @override
  ConsumerState<ReadHistoryPage> createState() => _ReadHistoryPageState();
}

class _ReadHistoryPageState extends ConsumerState<ReadHistoryPage> {
  @override
  void initState() {
    super.initState();
    // 从阅读器返回时进度会变，进页面就重读一次账本。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(readingHistoryProvider.notifier).reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = ref.watch(readingHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.canPop() ? context.pop() : context.go('/mine'),
        ),
        title: const Text('阅读历史'),
        actions: <Widget>[
          if (entries.isNotEmpty)
            TextButton(
              onPressed: _confirmClear,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                textStyle: AppTypography.caption,
              ),
              child: const Text('清空'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: entries.isEmpty
          ? const EmptyState(
              illustration: AppIllustrations.emptySearch,
              title: '还没有阅读记录',
              description: '打开任意一本开始阅读，这里会记下读到第几页。',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              itemCount: entries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HistoryTile(
                  entry: entry,
                  onTap: () => _openReader(entry),
                  onLongPress: () => _showEntryMenu(entry),
                );
              },
            ),
    );
  }

  Future<void> _openReader(ReadingHistoryEntry entry) async {
    final query = <String, String>{
      'album': entry.albumId,
      'chapter': entry.chapterId,
      'title': entry.progress.chapterTitle,
      'albumTitle': entry.progress.albumTitle,
      'page': '${entry.progress.page}',
    };
    await context.push('/reader?${Uri(queryParameters: query).query}');
    if (mounted) ref.read(readingHistoryProvider.notifier).reload();
  }

  Future<void> _showEntryMenu(ReadingHistoryEntry entry) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(
                entry.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(entry.subtitle),
            ),
            const Divider(height: 1),
            ListTile(
              leading: IconTheme(
                data: IconThemeData(color: Theme.of(context).colorScheme.error),
                child: const SvgIcon(AppIcons.trash, size: 20),
              ),
              title: Text(
                '删除这条记录',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action != 'remove') return;
    await ref.read(readingHistoryProvider.notifier).remove(entry);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已删除该条阅读记录')));
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空阅读历史'),
        content: const Text('只清空「读到第几页」的记录，不影响收藏与下载。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(readingHistoryProvider.notifier).clear();
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });

  final ReadingHistoryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = entry.progress;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppColors.radiusCard),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 56,
                height: 76,
                child: CoverImage(albumId: entry.albumId, radius: 10),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.displayTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyStrong
                          .copyWith(color: scheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.micro
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.ratio,
                        minHeight: 4,
                        backgroundColor: scheme.surfaceContainerHigh,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Text(
                          '${progress.percent}%',
                          style: AppTypography.micro
                              .copyWith(color: scheme.primary),
                        ),
                        const Spacer(),
                        Text(
                          entry.displayTime,
                          style: AppTypography.micro
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(width: 6),
                        IconTheme(
                          data: IconThemeData(color: scheme.onSurfaceVariant),
                          child: const SvgIcon(AppIcons.forward, size: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
