import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/models/favorite_item.dart';
import '../home/home_likes.dart';
import '../home/widgets/album_card.dart';
import '../home/widgets/feed_skeleton.dart';
import 'collect_providers.dart';
import 'favorites_sync.dart';

/// 收藏页：本地账本优先，登录后可与服务端对账。
class CollectPage extends ConsumerStatefulWidget {
  const CollectPage({super.key});

  @override
  ConsumerState<CollectPage> createState() => _CollectPageState();
}

class _CollectPageState extends ConsumerState<CollectPage> {
  String _folderId = 'all';
  bool _sortByUpdate = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = ref.watch(favoritesItemsProvider);
    final folders = ref.watch(favoritesFoldersProvider);
    final session = ref.watch(accountSessionProvider).valueOrNull;
    final loggedIn = session?.isLoggedIn ?? false;
    final syncState = ref.watch(favoritesSyncProvider);
    final syncing = syncState.busy;

    final visible = _filtered(items);
    final activeCount = items.where((item) => item.hasUpdate).length;

    return AppGlassPage(
      appBar: AppGlassAppBar(
        leading: AppIconButton(
          tooltip: '返回',
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/mine'),
        ),
        title: const Text('我的收藏'),
        actions: <Widget>[
          if (loggedIn)
            AppIconButton(
              tooltip: '同步收藏',
              onPressed: syncing ? null : _sync,
              icon: syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: AppProgressIndicator.circular(strokeWidth: 2),
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
                  onLongPress: folder.id == 'default'
                      ? null
                      : () => _deleteFolder(folder),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
            child: Row(
              children: <Widget>[
                AppChip(
                  kind: AppChipKind.choice,
                  label: const Text('收藏时间'),
                  selected: !_sortByUpdate,
                  onTap: () => setState(() => _sortByUpdate = false),
                ),
                const SizedBox(width: 8),
                AppChip(
                  kind: AppChipKind.choice,
                  label: const Text('更新时间'),
                  selected: _sortByUpdate,
                  onTap: () => setState(() => _sortByUpdate = true),
                ),
                if (activeCount > 0)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '$activeCount 本有更新',
                        textAlign: TextAlign.end,
                        style:
                            AppTypography.micro.copyWith(color: scheme.primary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? EmptyState(
                    illustration: AppIllustrations.emptySearch,
                    title: items.isEmpty ? '还没有收藏' : '这个文件夹还没有收藏',
                    description: '在详情页点右上角五角星即可收藏；登录后会自动双向同步。',
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      // 卡片正文含标题 2 行 + 作者 + 标签行：按字号放宽，避免溢出。
                      childAspectRatio: albumGridAspectRatio(context),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final item = visible[index];
                      return Stack(
                        children: <Widget>[
                          AlbumCard(
                            album: withScrapedLikes(
                              item.toSummary(),
                              ref.watch(albumLikesProvider).likes,
                            ),
                            onTap: () => context.push('/album/${item.albumId}'),
                            onLongPress: () => _showItemMenu(item),
                          ),
                          if (item.hasUpdate)
                            Positioned(
                              right: 6,
                              bottom: 62,
                              child: IgnorePointer(
                                child: AppBadge(
                                  label: const Text(
                                    '更新',
                                    style: AppTypography.micro,
                                  ),
                                  color: scheme.primary,
                                  metalChild: Container(
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
                                      style: AppTypography.micro
                                          .copyWith(color: scheme.onPrimary),
                                    ),
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
                                      : AppIcons.star,
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
    final report = await ref.read(favoritesSyncProvider.notifier).syncNow();
    if (!mounted) return;
    if (report == null) {
      final error = ref.read(favoritesSyncProvider).lastError ?? '未知错误';
      AppToast.show(
        context,
        '同步失败：$error',
        duration: const Duration(seconds: 4),
      );
      return;
    }
    AppToast.show(
      context,
      '同步完成：云端 ${report.serverCount} 本 · 拉回 ${report.addedToLocal} 本'
      ' · 上传 ${report.pushed} 本'
      '${report.conflicts > 0 ? '，${report.conflicts} 条冲突已自愈' : ''}',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _createFolder() async {
    var folderName = '';
    final name = await AppDialog.show<String>(
      context: context,
      title: '新建文件夹',
      contentBuilder: (_) => AppTextField(
        autofocus: true,
        decoration: const InputDecoration(hintText: '文件夹名'),
        onChanged: (value) => folderName = value,
      ),
      actions: <AppDialogAction<String>>[
        const AppDialogAction(label: '取消'),
        AppDialogAction(
          label: '创建',
          primary: true,
          resultBuilder: () => folderName,
        ),
      ],
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    await ref.read(favoritesRepositoryProvider).createFolder(name);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteFolder(FavoriteFolder folder) async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      title: '删除「${folder.name}」',
      message: '文件夹里的收藏不会被删除，只会回到「默认」。',
      actions: const <AppDialogAction<bool>>[
        AppDialogAction(label: '取消', result: false),
        AppDialogAction(
          label: '删除',
          result: true,
          primary: true,
          destructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await ref.read(favoritesRepositoryProvider).deleteFolder(folder.id);
    if (!mounted) return;
    setState(() => _folderId = 'all');
  }

  Future<void> _showItemMenu(FavoriteItem item) async {
    final folders = ref.read(favoritesFoldersProvider);
    final action = await AppSheet.show<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppListTile(
                title: Text(
                  item.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(item.sync.label),
              ),
              const Divider(height: 1),
              for (final folder in folders)
                AppListTile(
                  leading: const IconTheme(
                    data: IconThemeData(),
                    child: SvgIcon(AppIcons.folder, size: 20),
                  ),
                  title: Text('移到「${folder.name}」'),
                  enabled: !item.folderIds.contains(folder.id),
                  onTap: () => Navigator.of(context).pop('folder:${folder.id}'),
                ),
              AppListTile(
                leading: IconTheme(
                  data:
                      IconThemeData(color: Theme.of(context).colorScheme.error),
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
      ),
    );
    if (action == null || !mounted) return;

    final repository = ref.read(favoritesRepositoryProvider);
    final items = ref.read(favoritesItemsProvider.notifier);
    if (action == 'remove') {
      await repository.remove(item.albumId);
    } else if (action.startsWith('folder:')) {
      await repository.moveToFolder(item.albumId, action.substring(7));
    }
    items.reload();
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
    final glass = context.isLiquidGlass;
    return GestureDetector(
      onTap: glass ? null : onTap,
      onLongPress: onLongPress,
      child: AppChip(
        kind: AppChipKind.choice,
        label: Text(label),
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        metalChild: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
            border: Border.all(
              color: selected ? Colors.transparent : scheme.outline,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.caption.copyWith(
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
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
    final radius = BorderRadius.circular(AppColors.radiusCard);
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      borderRadius: radius,
      color: scheme.primaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      metalDecoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: radius,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '本地收藏 · 登录后可同步',
              style: AppTypography.micro
                  .copyWith(color: scheme.onPrimaryContainer),
            ),
          ),
          AppButton.text(
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
