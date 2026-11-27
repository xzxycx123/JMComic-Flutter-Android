import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/config/app_config.dart';
import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/interface_style_selector.dart';
import '../../core/theme/theme_mode_selector.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../core/utils/file_names.dart';
import '../../core/utils/host_normalizer.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/jm_host_entry.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sources/jm_host_probe.dart';
import '../collect/collect_providers.dart';
import '../download/download_providers.dart';
import '../home/widgets/section_header.dart';
import '../update/update_dialog.dart';
import '../update/update_providers.dart';

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
    final update = ref.watch(updateCheckProvider);

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
            trailing: AppSwitch.adaptive(
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
            trailing: AppSwitch.adaptive(
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
          const ThemeModeSelector(),
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
            trailing: AppSwitch.adaptive(
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
            title: '保存图片目录',
            value: settings.saveImagePath,
            onTap: () => _editSaveImagePath(settings.saveImagePath),
          ),
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
          const SectionHeader(title: '更新'),
          _SettingsTile(
            icon: AppIcons.refresh,
            title: '自动检查更新',
            value: settings.autoUpdateCheck ? '启动时检查' : '已关闭',
            trailing: AppSwitch.adaptive(
              value: settings.autoUpdateCheck,
              onChanged: (value) =>
                  ref.read(settingsProvider.notifier).setAutoUpdateCheck(value),
            ),
          ),
          _SettingsTile(
            icon: AppIcons.download,
            title: '检查新版本',
            value: update.summary,
            busy: update.checking,
            onTap: _checkUpdate,
          ),
          _SettingsTile(
            icon: AppIcons.check,
            title: '当前版本',
            value: update.currentVersion.isKnown
                ? update.currentVersion.display
                : 'v${AppConfig.appVersion}',
          ),
          if (settings.skippedReleaseTag.isNotEmpty)
            _SettingsTile(
              icon: AppIcons.close,
              title: '已跳过 ${settings.skippedReleaseTag}',
              value: '点此恢复提醒',
              onTap: _clearSkippedRelease,
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

  void _showToast(String message) {
    if (!mounted) return;
    AppToast.show(context, message, duration: const Duration(seconds: 4));
  }

  Future<void> _clearSavedPassword() async {
    await ref.read(authRepositoryProvider).forgetPassword();
    _showToast('已清除保存的密码');
  }

  Future<void> _rediscover() async {
    setState(() => _busy = true);
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      final repository = ref.read(sessionRepositoryProvider);
      await repository.rediscover();
      // 仓储持有的是旧的 JmApi 实例，必须一起作废，否则回首页仍是旧线路。
      container.invalidate(jmBootstrapProvider);
      container.invalidate(homeRepositoryProvider);
      if (!mounted) return;
      final report = repository.lastReport;
      setState(() => _reportSummary = report?.summary ?? '');
      _showToast('线路已刷新：${repository.current.apiHost}');
    } catch (error) {
      _showToast('重新探测失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 全量测速：所有已知 API 线路 + 图床跑一遍，结果直接列在设置页。
  Future<void> _probeLines() async {
    setState(() => _probing = true);
    try {
      final report = await ref.read(sessionRepositoryProvider).probeAll();
      if (!mounted) return;
      setState(() {
        _probeResults = report.probes;
        _reportSummary = report.summary;
      });
      _showToast('测速完成：${report.message}');
    } catch (error) {
      _showToast('测速失败：$error');
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _editManualHost() async {
    final current = ref.read(sessionRepositoryProvider).manualHost;
    var text = current;
    final value = await AppDialog.show<String>(
      context: context,
      title: '手动填写域名',
      contentBuilder: (_) => _ManualHostField(
        initialValue: current,
        onChanged: (value) => text = value,
      ),
      actions: <AppDialogAction<String>>[
        const AppDialogAction(label: '取消'),
        AppDialogAction(
          label: '保存',
          primary: true,
          resultBuilder: () => text.trim(),
        ),
      ],
    );
    if (value == null || !mounted) return;
    final container = ProviderScope.containerOf(context, listen: false);
    await ref.read(sessionRepositoryProvider).setManualHost(value);
    container.invalidate(jmBootstrapProvider);
    _showToast(value.isEmpty ? '已清除手动域名' : '已保存：$value');
  }

  /// 阅读器「下载当页图片」的保存目录：默认 `Pictures/JMComicDownloader/`，清空即回落默认。
  Future<void> _editSaveImagePath(String current) async {
    var text = current;
    final value = await AppDialog.show<String>(
      context: context,
      title: '保存图片目录',
      contentBuilder: (_) => _SavePathField(
        initialValue: current,
        onChanged: (value) => text = value,
      ),
      actions: <AppDialogAction<String>>[
        const AppDialogAction(label: '取消'),
        AppDialogAction(
          label: '保存',
          primary: true,
          resultBuilder: () => normalizeSaveDir(text),
        ),
      ],
    );
    if (value == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setSaveImagePath(value);
    _showToast('保存目录：$value');
  }

  /// 手动检查更新：有新版就弹「检测到新版本」（用户主动点的，无视跳过记录）。
  Future<void> _checkUpdate() async {
    final state = await ref.read(updateCheckProvider.notifier).check();
    if (!mounted) return;
    final release = state.release;
    if (release == null) {
      _showToast(
        state.phase == UpdatePhase.failed
            ? '检查失败：${state.message}'
            : '已是最新版本 ${state.currentVersion.display}',
      );
      return;
    }
    await promptForRelease(
      context: context,
      ref: ref,
      release: release,
      current: state.currentVersion,
    );
  }

  /// 取消「跳过此版本」，下次启动恢复提醒。
  Future<void> _clearSkippedRelease() async {
    await ref.read(updateCheckProvider.notifier).clearSkipped();
    _showToast('已恢复更新提醒');
  }

  Future<void> _pickReaderMode(String current) async {
    final selected = await AppSheet.show<String>(
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
              AppListTile(
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
    if (selected != null && mounted) {
      await ref.read(settingsProvider.notifier).setDefaultReaderMode(selected);
    }
  }

  Future<void> _showLocation() async {
    final location =
        await ref.read(downloadRepositoryProvider).describeLocation();
    _showToast('导出目录：$location');
  }

  Future<void> _clearTemp() async {
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
      // 顺带清掉没装成的更新包（jm-update/）。
      await ref.read(updateRepositoryProvider).clearDownloads();
      _showToast('已清理 $removed 个临时目录');
    } catch (error) {
      _showToast('清理失败：$error');
    }
  }

  Future<void> _clearImageCache() async {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _showToast('封面缓存已清理');
  }

  Future<void> _exportRecords() async {
    final records = ref.read(downloadRecordsProvider);
    final payload =
        records.map((record) => record.toJson()).toList(growable: false);
    await Clipboard.setData(ClipboardData(text: payload.toString()));
    _showToast('已复制 ${records.length} 条记录到剪贴板');
  }
}

class _ManualHostField extends StatefulWidget {
  const _ManualHostField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_ManualHostField> createState() => _ManualHostFieldState();
}

class _ManualHostFieldState extends State<_ManualHostField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '如 www.cdnutc.cc'),
        onChanged: widget.onChanged,
      );
}

/// 保存图片目录输入框（对话框内容）。
class _SavePathField extends StatefulWidget {
  const _SavePathField({required this.initialValue, required this.onChanged});

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_SavePathField> createState() => _SavePathFieldState();
}

class _SavePathFieldState extends State<_SavePathField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppTextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: defaultSaveImageDir,
          helperText: Platform.isAndroid
              ? '输入以 Pictures、DCIM、Download 或 Documents 开头的路径'
              : null,
          helperMaxLines: 2,
        ),
        onChanged: widget.onChanged,
      );
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
    if (context.isLiquidGlass) {
      return AppSurface(
        kind: AppSurfaceKind.controlGroup,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        margin: const EdgeInsets.only(bottom: 8),
        child: AppListTile(
          leading: SvgIcon(icon, size: 20, color: scheme.onSurfaceVariant),
          title: Text(title, style: AppTypography.body),
          subtitle: value == null || value!.isEmpty
              ? null
              : Text(value!, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: AppProgressIndicator.circular(strokeWidth: 2),
                )
              : trailing,
          onTap: busy ? null : onTap,
        ),
      );
    }
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
                    child: AppProgressIndicator.circular(strokeWidth: 2),
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

    final radius = BorderRadius.circular(AppColors.radiusCard);
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      borderRadius: radius,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: radius,
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
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: AppBadge(
                        label: const Text('国内', style: AppTypography.micro),
                        color: scheme.primary,
                        metalChild: Container(
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
