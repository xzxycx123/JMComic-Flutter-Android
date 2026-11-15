import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/account_session.dart';
import '../../data/models/user_session.dart';
import '../collect/collect_providers.dart';
import '../download/download_providers.dart';
import '../home/widgets/section_header.dart';

/// 我的：资料卡 + 统计 + 五组设置入口。
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final favoriteCount = ref.watch(favoriteCountProvider);
    final account = ref.watch(accountSessionProvider).valueOrNull;
    final completed = ref.watch(completedDownloadCountProvider);
    final activeDownloads = ref.watch(activeDownloadCountProvider);
    final historyCount = ref
        .watch(downloadRecordsProvider)
        .where((record) => record.isFinished)
        .length;
    final progressCount = ref.watch(progressStoreProvider).historyCount;
    final session = ref.watch(sessionProvider).valueOrNull;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: <Widget>[
            _ProfileCard(session: session),
            const SizedBox(height: 16),
            _StatsRow(
              items: <({String label, String value})>[
                (label: '下载完成', value: '$completed'),
                (label: '收藏', value: '$favoriteCount'),
                (label: '阅读历史', value: '$progressCount'),
              ],
            ),
            const SizedBox(height: 18),
            const SectionHeader(title: '账号与收藏'),
            _AccountCard(
              account: account,
              onLogin: () => context.push('/login'),
              onLogout: () => _confirmLogout(context, ref),
            ),
            _SettingTile(
              icon: AppIcons.bookmark,
              title: '我的收藏',
              value: favoriteCount > 0 ? '$favoriteCount 本' : '暂无收藏',
              onTap: () => context.push('/collect'),
            ),
            const SizedBox(height: 10),
            const SectionHeader(title: '下载与历史'),
            _SettingTile(
              icon: AppIcons.download,
              title: '下载',
              value: activeDownloads > 0 ? '$activeDownloads 个进行中' : '输入车号新建任务',
              onTap: () => context.push('/download'),
            ),
            _SettingTile(
              icon: AppIcons.list,
              title: '历史记录',
              value: historyCount > 0 ? '$historyCount 条' : '暂无记录',
              onTap: () => context.push('/history'),
            ),
            const SizedBox(height: 10),
            const SectionHeader(title: '阅读'),
            _SettingTile(
              icon: AppIcons.bookOpen,
              title: '默认阅读模式',
              value: settings.defaultReaderMode == 'vertical' ? '上下滚动' : '左右翻页',
              onTap: () => _pickReaderMode(context, ref, settings.defaultReaderMode),
            ),
            _SettingTile(
              icon: AppIcons.pageMode,
              title: '翻页动画',
              trailing: Switch.adaptive(
                value: settings.pageTurnAnimation,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setPageTurnAnimation(value),
              ),
            ),
            const SizedBox(height: 10),
            const SectionHeader(title: '外观'),
            _SettingTile(
              icon: AppIcons.theme,
              title: '主题模式',
              value: settings.themeMode.label,
              onTap: () => _pickTheme(context, ref, settings.themeMode),
            ),
            const SizedBox(height: 10),
            const SectionHeader(title: '网络'),
            _SettingTile(
              icon: AppIcons.refresh,
              title: '当前线路',
              value: session == null || session.apiHost.isEmpty ? '探测中' : session.apiHost,
              onTap: () => context.push('/mine/settings'),
            ),
            _SettingTile(
              icon: AppIcons.settings,
              title: '自动切换线路',
              trailing: Switch.adaptive(
                value: settings.autoSwitchHost,
                onChanged: (value) =>
                    ref.read(settingsProvider.notifier).setAutoSwitchHost(value),
              ),
            ),
            const SizedBox(height: 10),
            const SectionHeader(title: '存储与关于'),
            _SettingTile(
              icon: AppIcons.folder,
              title: '默认下载目录',
              value: 'Documents/JMComics',
              onTap: () => _copyPath(context, ref),
            ),
            _SettingTile(
              icon: AppIcons.settings,
              title: '全部设置',
              onTap: () => context.push('/mine/settings'),
            ),
            _SettingTile(
              icon: AppIcons.check,
              title: '关于 JMComic',
              value: 'v${AppConfig.appVersion}',
              onTap: () => context.push('/mine/about'),
            ),
            const SizedBox(height: 14),
            Text(
              '本地模式：v1 不接入登录 / 收藏同步 / 评论。',
              style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后收藏仍保留在本机，但不会再同步到账号。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(accountSessionProvider.notifier).logout();
  }

  Future<void> _copyPath(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final location = await ref.read(downloadRepositoryProvider).describeLocation();
    messenger.showSnackBar(SnackBar(content: Text('目录：$location')));
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, AppThemeMode current) async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OptionSheet<AppThemeMode>(
        title: '主题模式',
        options: AppThemeMode.values,
        current: current,
        labelOf: (mode) => mode.label,
      ),
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setThemeMode(selected);
    }
  }

  Future<void> _pickReaderMode(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final options = <String>['paged', 'vertical'];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => _OptionSheet<String>(
        title: '默认阅读模式',
        options: options,
        current: current,
        labelOf: (value) => value == 'vertical' ? '上下滚动' : '左右翻页',
      ),
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setDefaultReaderMode(selected);
    }
  }
}

/// 账号卡：未登录时给登录入口，已登录时显示用户名 / 收藏额度 / 上次同步。
class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.onLogin,
    required this.onLogout,
  });

  final AccountSession? account;
  final VoidCallback onLogin;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = account ?? AccountSession.local;
    final loggedIn = session.isLoggedIn;

    final subtitle = switch (session.state) {
      SessionState.valid => session.username.isEmpty ? '已登录' : session.username,
      SessionState.needsLogin => '登录已失效 · 点击重新登录',
      SessionState.local => '未登录 · 本地收藏（登录后可同步）',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          IconTheme(
            data: IconThemeData(color: scheme.onSurfaceVariant),
            child: const SvgIcon(AppIcons.user, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
                if (loggedIn) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    '收藏 ${session.favoritesCount}'
                    '${session.favoritesMax > 0 ? ' / ${session.favoritesMax}' : ''}'
                    '${session.lastSyncAt > 0 ? ' · 上次同步 ${_clock(session.lastSyncAt)}' : ''}',
                    style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (session.nearLimit) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      session.atLimit ? '收藏已满，请先取消部分收藏' : '收藏接近上限（90%）',
                      style: AppTypography.micro.copyWith(color: scheme.error),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (loggedIn)
            TextButton(
              onPressed: onLogout,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                textStyle: AppTypography.caption,
                minimumSize: const Size(0, 32),
              ),
              child: const Text('退出'),
            )
          else
            TextButton(
              onPressed: onLogin,
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                textStyle: AppTypography.caption,
                minimumSize: const Size(0, 32),
              ),
              child: Text(session.needsLogin ? '重新登录' : '登录'),
            ),
        ],
      ),
    );
  }

  static String _clock(int timestamp) {
    final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({this.session});

  final UserSession? session;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primaryContainer,
            scheme.surfaceContainer,
          ],
        ),
        borderRadius: BorderRadius.circular(AppColors.radiusPanel),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          const BrandMark(size: 56, radius: 999),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '未登录 · 本地模式',
                  style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: 4),
                Text(
                  session == null || session!.apiHost.isEmpty
                      ? '正在探测可用线路'
                      : '${session!.apiHost} · ${session!.displayImageHost}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.items});

  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          for (final item in items)
            Expanded(
              child: Column(
                children: <Widget>[
                  Text(
                    item.value,
                    style: AppTypography.title.copyWith(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.label,
                    style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
  });

  final String icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: <Widget>[
                IconTheme(
                  data: IconThemeData(color: scheme.onSurfaceVariant),
                  child: SvgIcon(icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.body.copyWith(color: scheme.onSurface),
                  ),
                ),
                if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (trailing != null) trailing!,
                if (trailing == null && onTap != null) ...<Widget>[
                  const SizedBox(width: 6),
                  IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.forward, size: 18),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.labelOf,
  });

  final String title;
  final List<T> options;
  final T current;
  final String Function(T option) labelOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: AppTypography.sectionTitle.copyWith(color: scheme.onSurface),
              ),
            ),
          ),
          for (final option in options)
            ListTile(
              title: Text(
                labelOf(option),
                style: AppTypography.body.copyWith(color: scheme.onSurface),
              ),
              trailing: option == current
                  ? IconTheme(
                      data: IconThemeData(color: scheme.primary),
                      child: const SvgIcon(AppIcons.check, size: 20),
                    )
                  : null,
              onTap: () => Navigator.of(context).pop(option),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
