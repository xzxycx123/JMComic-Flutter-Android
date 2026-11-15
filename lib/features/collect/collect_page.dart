import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/models/favorite_item.dart';
import '../home/widgets/album_card.dart';
import '../home/widgets/feed_skeleton.dart';
import 'collect_providers.dart';

/// 收藏页：本地账本优先，登录后可与服务端对账。
class CollectPage extends ConsumerStatefulWidget {
  const CollectPage({super.key});

  @override
  ConsumerState<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends ConsumerState<CollectPage> {
  String _folderId = 'all';
  bool _sortByUpdate = false;
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(favoritesItemsProvider);
    final folders = ref.watch(favoritesFoldersProvider);
    final session = ref.watch(accountSessionProvider).valueOrNull;
    final loggedIn = session?.isLoggedIn ?? false;

    final visible = _filtered(items);
    final activeCount = items.where((item) => item.hasUpdate).length;

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
        title: const Text('我的收藏'),
        actions: <Widget>[
          if (loggedIn)
            IconButton(
              tooltip: '同步收藏',
              onPressed: _syncing ? null : _sync,
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconTheme(
                      data: IconThemeData(color: scheme.onSurface),
                      child: const SvgIcon(AppIcons.refresh, size: 20),
                    ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: <Widget>[
          if (!loggedIn) _SyncBanner(onLogin: () => context.push('/login')),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              itemCount: folders.length + 2,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _FolderChip(
                    label: '全部 ${items.length}',
                    selected: _folderId == 'all',
                    onTap: () => setState(() => _folderId = 'all'),
                  );
                }
                if (index == folders.length + 1) {
                  return _FolderChip(
                    label: '+ 新建',
                    selected: false,
                    onTap: _createFolder,
                  );
                }
                final folder = folders[index - 1];
                return _FolderChip(
                  label: folder.name,
                  selected: _folderId == folder.id,
                  onTap: () => setState(() => _folderId = folder.id),
                  onLongPress: folder.id == 'default' ? null : () => _deleteFolder(folder),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: const Text('收藏时间'),
                  selected: !_sortByUpdate,
                  onSelected: (_) => setState(() => _sortByUpdate = false),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('更新时间'),
                  selected: _sortByUpdate,
                  onSelected: (_) => setState(() => _sortByUpdate = true),
                ),
                const Spacer(),
                if (activeCount > 0)
                  Text(
                    '$activeCount 本有更新',
                    style: AppTypography.micro.copyWith(color: scheme.primary),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    illustration: AppIllustrations.emptySearch,
                    title: items.isEmpty ? '还没有收藏' : '这个文件夹还没有收藏',
                    description: '在详情页点右上角书签即可收藏；登录后还能同步到账号。',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.52,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Stack(
                        children: <Widget>[
                          AlbumCard(
                            album: item.toSummary(),
                            onTap: () => context.push('/album/${item.albumId}'),
                            onLongPress: () => _showItemMenu(item),
                          ),
                          if (item.hasUpdate)
                            Positioned(
                              right: 6,
                              bottom: 62,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '更新',
                                  style: AppTypography.micro.copyWith(
                                    color: scheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          if (item.sync != FavoriteSyncState.synced)
                            Positioned(
                              left: 8,
                              bottom: 62,
                              child: IconTheme(
                                data: IconThemeData(
                                  color: item.sync == FavoriteSyncState.conflict
                                      ? scheme.error
                                      : scheme.onSurfaceVariant,
                                ),
                                child: SvgIcon(
                                  item.sync == FavoriteSyncState.conflict
                                      ? AppIcons.alert
                                      : AppIcons.bookmark,
                                  size: 14,
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<FavoriteItem> _filtered(List<FavoriteItem> items) {
    final list = _folderId == 'all'
        ? List<FavoriteItem>.from(items)
        : items.where((item) => item.folderIds.contains(_folderId)).toList();
    list.sort(
      (a, b) => _sortByUpdate
          ? b.updateAt.compareTo(a.updateAt)
          : b.addedAt.compareTo(a.addedAt),
    );
    return list;
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(favoritesRepositoryProvider);
      final report = await repository.sync();
      ref.read(favoritesItemsProvider.notifier).reload();
      await ref.read(accountSessionProvider.notifier).updateCount(report.serverCount);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '同步完成：推送 ${report.pushed} 条'
            '${report.conflicts > 0 ? '，${report.conflicts} 条冲突已自愈' : ''}',
          ),
        ),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('同步失败：$error')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    await ref.read(favoritesRepositoryProvider).createFolder(name);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteFolder(FavoriteFolder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除「${folder.name}」'),
        content: const Text('文件夹里的收藏不会被删除，只会回到「默认」。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(favoritesRepositoryProvider).deleteFolder(folder.id);
    if (!mounted) return;
    setState(() => _folderId = 'all');
  }

  Future<void> _showItemMenu(FavoriteItem item) async {
    final folders = ref.read(favoritesFoldersProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              title: Text(item.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(item.sync.label),
            ),
            const Divider(height: 1),
            for (final folder in folders)
              ListTile(
                leading: const IconTheme(
                  data: IconThemeData(),
                  child: SvgIcon(AppIcons.folder, size: 20),
                ),
                title: Text('移到「${folder.name}」'),
                enabled: !item.folderIds.contains(folder.id),
                onTap: () => Navigator.of(context).pop('folder:${folder.id}'),
              ),
            ListTile(
              leading: IconTheme(
                data: IconThemeData(color: Theme.of(context).colorScheme.error),
                child: const SvgIcon(AppIcons.trash, size: 20),
              ),
              title: Text(
                '取消收藏',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop('remove'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null) return;

    final repository = ref.read(favoritesRepositoryProvider);
    if (action == 'remove') {
      await repository.remove(item.albumId);
    } else if (action.startsWith('folder:')) {
      await repository.moveToFolder(item.albumId, action.substring(7));
    }
    ref.read(favoritesItemsProvider.notifier).reload();
    if (mounted) setState(() {});
  }
}

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primary : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
          border: Border.all(color: selected ? Colors.transparent : scheme.outline),
        ),
        child: Text(
          label,
          style: AppTypography.caption.copyWith(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '本地收藏 · 登录后可同步',
              style: AppTypography.micro.copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
          TextButton(
            onPressed: onLogin,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onPrimaryContainer,
              minimumSize: const Size(0, 32),
            ),
            child: const Text('去登录'),
          ),
        ],
      ),
    );
  }
}
