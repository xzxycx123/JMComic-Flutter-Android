import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/interface_style_selector.dart';
import '../../core/utils/host_normalizer.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/jm_host_entry.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sources/jm_host_probe.dart';
import '../collect/collect_providers.dart';
import '../download/download_providers.dart';
import '../home/widgets/section_header.dart';

/// 设置页：阅读 / 外观 / 网络 / 存储 四组，全部即时生效。
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _busy = false;
  bool _probing = false;
  List<JmHostProbeResult> _probeResults = const <JmHostProbeResult>[];
  String _reportSummary = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final session = ref.watch(sessionProvider);
    final records = ref.watch(downloadRecordsProvider);

    return Scaffold(
      backgroundColor: settings.interfaceStyle == AppInterfaceStyle.liquidGlass
          ? Colors.transparent
          : null,
      appBar: AppBar(
        leading: IconButton(
          icon: IconTheme(
            data: IconThemeData(color: scheme.onSurface),
            child: const SvgIcon(AppIcons.back, size: 22),
          ),
          onPressed: () => context.pop(),
        ),
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const SectionHeader(title: '阅读'),
          _SettingsTile(
            icon: AppIcons.bookOpen,
            title: '默认阅读模式',
            value: settings.defaultReaderMode == 'vertical' ? '上下滚动' : '左右翻页',
            onTap: () => _pickReaderMode(settings.defaultReaderMode),
          ),
          _SettingsTile(
            icon: AppIcons.pageMode,
            title: '翻页动画',
            trailing: Switch.adaptive(
              value: settings.pageTurnAnimation,
              onChanged: (value) => ref
                  .read(settingsProvider.notifier)
                  .setPageTurnAnimation(value),
            ),
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: '账号'),
          _SettingsTile(
            icon: AppIcons.user,
            title: '记住密码（自动登录）',
            value: settings.rememberPassword ? '已开启' : '已关闭',
            trailing: Switch.adaptive(
              value: settings.rememberPassword,
              onChanged: (value) => _setRememberPassword(value),
            ),
          ),
          _SettingsTile(
            icon: AppIcons.trash,
            title: '清除已保存的密码',
            onTap: _clearSavedPassword,
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: '外观'),
          const InterfaceStyleSelector(),
          _SettingsTile(
            icon: AppIcons.theme,
            title: '主题模式',
            value: settings.themeMode.label,
            onTap: () => _pickTheme(settings.themeMode),
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: '网络'),
          _SettingsTile(
            icon: AppIcons.refresh,
            title: '当前 API 线路',
            value: session.valueOrNull?.apiHost ?? '探测中',
          ),
          _SettingsTile(
            icon: AppIcons.download,
            title: '当前图床',
            value: session.valueOrNull?.displayImageHost ?? '未获取',
          ),
          _SettingsTile(
            icon: AppIcons.check,
            title: 'appVersion（tokenparam）',
            value: session.valueOrNull?.appVersion ?? '2.1.13',
          ),
          _SettingsTile(
            icon: AppIcons.settings,
            title: '自动切换线路',
            trailing: Switch.adaptive(
              value: settings.autoSwitchHost,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setAutoSwitchHost(value),
            ),
          ),
          _SettingsTile(
            icon: AppIcons.refresh,
            title: '重新探测线路',
            value: _reportSummary,
            busy: _busy,
            onTap: _rediscover,
          ),
          _SettingsTile(
            icon: AppIcons.search,
            title: '线路测速',
            value:
                '${_probeResults.where((item) => item.kind == JmHostKind.api && item.ok).length}'
                '/${_probeResults.where((item) => item.kind == JmHostKind.api).length} 可用',
            busy: _probing,
            onTap: _probeLines,
          ),
          if (_probeResults.isNotEmpty) _LineStatusList(results: _probeResults),
          _SettingsTile(
            icon: AppIcons.forward,
            title: '手动填写域名',
            value: ref.watch(sessionRepositoryProvider).manualHost,
            onTap: _editManualHost,
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: '存储'),
          _SettingsTile(
            icon: AppIcons.folder,
            title: '默认下载目录',
            value: 'Documents/JMComics',
            onTap: _showLocation,
          ),
          _SettingsTile(
            icon: AppIcons.trash,
            title: '清理临时文件',
            onTap: _clearTemp,
          ),
          _SettingsTile(
            icon: AppIcons.close,
            title: '清理封面缓存',
            onTap: _clearImageCache,
          ),
          _SettingsTile(
            icon: AppIcons.share,
            title: '导出下载记录',
            value: '${records.length} 条',
            onTap: _exportRecords,
          ),
          const SizedBox(height: 8),
          const SectionHeader(title: '关于'),
          _SettingsTile(
            icon: AppIcons.check,
            title: '版本与开源许可',
            onTap: () => context.push('/mine/about'),
          ),
          const SizedBox(height: 16),
          Text(
            '排障：接口异常时先跑 tools\\probe_hosts.ps1 刷新内置线路种子（含国内域名）；本机代理请用 --dart-define=JM_PROXY=...',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// 关闭时顺手清掉已保存的密码，避免「关了却还能自动登」。
  Future<void> _setRememberPassword(bool value) async {
    await ref.read(settingsProvider.notifier).setRememberPassword(value);
    if (!value) await ref.read(authRepositoryProvider).forgetPassword();
  }

  Future<void> _clearSavedPassword() async {
    final messenger = ScaffoldMessenger.of(context);
    await ref.read(authRepositoryProvider).forgetPassword();
    messenger.showSnackBar(const SnackBar(content: Text('已清除保存的密码')));
  }

  Future<void> _rediscover() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repository = ref.read(sessionRepositoryProvider);
      await repository.rediscover();
      // 仓储持有的是旧的 JmApi 实例，必须一起作废，否则回首页仍是旧线路。
      ref.invalidate(jmBootstrapProvider);
      ref.invalidate(homeRepositoryProvider);
      if (mounted) {
        final report = repository.lastReport;
        setState(() => _reportSummary = report?.summary ?? '');
      }
      messenger.showSnackBar(
        SnackBar(content: Text('线路已刷新：${repository.current.apiHost}')),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('重新探测失败：$error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 全量测速：所有已知 API 线路 + 图床跑一遍，结果直接列在设置页。
  Future<void> _probeLines() async {
    setState(() => _probing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final report = await ref.read(sessionRepositoryProvider).probeAll();
      if (!mounted) return;
      setState(() {
        _probeResults = report.probes;
        _reportSummary = report.summary;
      });
      messenger.showSnackBar(SnackBar(content: Text('测速完成：${report.message}')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('测速失败：$error')));
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _editManualHost() async {
    final controller = TextEditingController(
      text: ref.read(sessionRepositoryProvider).manualHost,
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('手动填写域名'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如 www.cdnutc.cc'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    await ref.read(sessionRepositoryProvider).setManualHost(value);
    ref.invalidate(jmBootstrapProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value.isEmpty ? '已清除手动域名' : '已保存：$value')),
    );
  }

  Future<void> _pickTheme(AppThemeMode current) async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final mode in AppThemeMode.values)
              ListTile(
                title: Text(mode.label),
                trailing: mode == current
                    ? IconTheme(
                        data: IconThemeData(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: const SvgIcon(AppIcons.check, size: 20),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(mode),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setThemeMode(selected);
    }
  }

  Future<void> _pickReaderMode(String current) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final entry in <({String code, String label})>[
              (code: 'paged', label: '左右翻页'),
              (code: 'vertical', label: '上下滚动'),
            ])
              ListTile(
                title: Text(entry.label),
                trailing: entry.code == current
                    ? IconTheme(
                        data: IconThemeData(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: const SvgIcon(AppIcons.check, size: 20),
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(entry.code),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(settingsProvider.notifier).setDefaultReaderMode(selected);
    }
  }

  Future<void> _showLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final location =
        await ref.read(downloadRepositoryProvider).describeLocation();
    messenger.showSnackBar(SnackBar(content: Text('导出目录：$location')));
  }

  Future<void> _clearTemp() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cache = await getTemporaryDirectory();
      final workRoot =
          Directory('${cache.path}${Platform.pathSeparator}jm-pdf');
      var removed = 0;
      if (workRoot.existsSync()) {
        for (final entity in workRoot.listSync()) {
          entity.deleteSync(recursive: true);
          removed++;
        }
      }
      messenger.showSnackBar(SnackBar(content: Text('已清理 $removed 个临时目录')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('清理失败：$error')));
    }
  }

  Future<void> _clearImageCache() async {
    final messenger = ScaffoldMessenger.of(context);
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    messenger.showSnackBar(const SnackBar(content: Text('封面缓存已清理')));
  }

  Future<void> _exportRecords() async {
    final messenger = ScaffoldMessenger.of(context);
    final records = ref.read(downloadRecordsProvider);
    final payload =
        records.map((record) => record.toJson()).toList(growable: false);
    await Clipboard.setData(ClipboardData(text: payload.toString()));
    messenger
        .showSnackBar(SnackBar(content: Text('已复制 ${records.length} 条记录到剪贴板')));
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.value,
    this.trailing,
    this.onTap,
    this.busy = false,
  });

  final String icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: InkWell(
          onTap: busy ? null : onTap,
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
                if (busy)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (value != null)
                  Flexible(
                    child: Text(
                      value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: AppTypography.caption
                          .copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 测速结果列表：ok 按延迟升序排在前面，失败给出原因（超时 / TLS / 人机校验…）。
class _LineStatusList extends StatelessWidget {
  const _LineStatusList({required this.results});

  final List<JmHostProbeResult> results;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final api = results.where((item) => item.kind == JmHostKind.api).toList()
      ..sort((a, b) {
        if (a.ok != b.ok) return a.ok ? -1 : 1;
        return a.latencyMs.compareTo(b.latencyMs);
      });
    if (api.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
      ),
      child: Column(
        children: <Widget>[
          for (final item in api)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                  IconTheme(
                    data: IconThemeData(
                      color: item.ok ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    child: SvgIcon(
                      item.ok ? AppIcons.check : AppIcons.close,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.host,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption
                          .copyWith(color: scheme.onSurface),
                    ),
                  ),
                  if (isDomesticHost(item.host))
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '国内',
                        style: AppTypography.micro
                            .copyWith(color: scheme.onPrimaryContainer),
                      ),
                    ),
                  Text(
                    item.ok
                        ? '${item.latencyMs}ms'
                        : SessionRepository.statusLabel(item.status),
                    style: AppTypography.caption.copyWith(
                      color: item.ok ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
