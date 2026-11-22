import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/di/providers.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/local/settings_store.dart';
import '../../data/models/app_version.dart';
import '../../data/models/release_info.dart';
import '../../data/repositories/update_repository.dart';
import 'widgets/release_notes_view.dart';

/// 「检测到新版本」弹窗的三个出口。
enum UpdateChoice {
  /// 下载当前版本的 APK 并拉起系统安装器。
  install,

  /// 只关掉这次提醒，下次启动还会弹。
  later,

  /// 跳过这个 tag，下次不再提醒（更新版本照常提醒）。
  skip,
}

/// 应用内提示「有新版」的唯一入口：弹窗 -> 按选择分流。
///
/// 启动检查（[UpdateGate]）与设置页的「检查新版本」都走这里；
/// 「跳过此版本」只写 tag，下次启动由调用方决定是否忽略。
Future<void> promptForRelease({
  required BuildContext context,
  required WidgetRef ref,
  required ReleaseInfo release,
  required AppVersion current,
}) async {
  final choice = await showUpdateDialog(
    context: context,
    release: release,
    current: current,
  );
  if (!context.mounted) return;
  switch (choice) {
    case null:
    case UpdateChoice.later:
      // 取消 = 下次启动还会提醒，不写任何状态。
      return;
    case UpdateChoice.skip:
      await ref
          .read(settingsProvider.notifier)
          .setSkippedReleaseTag(release.tag);
      if (!context.mounted) return;
      AppToast.show(
        context,
        '已跳过 ${release.versionLabel}，下次启动不再提醒',
        duration: const Duration(seconds: 3),
      );
      return;
    case UpdateChoice.install:
      await installRelease(context: context, ref: ref, release: release);
      return;
  }
}

/// 双皮肤「检测到新版本」弹窗：标题 + release 页 readme + 安装 / 取消 / 跳过此版本。
Future<UpdateChoice?> showUpdateDialog({
  required BuildContext context,
  required ReleaseInfo release,
  required AppVersion current,
}) {
  return AppDialog.show<UpdateChoice>(
    context: context,
    title: '检测到新版本',
    contentBuilder: (context) =>
        _ReleasePanel(release: release, current: current),
    actions: <AppDialogAction<UpdateChoice>>[
      const AppDialogAction<UpdateChoice>(
        label: '安装',
        result: UpdateChoice.install,
        primary: true,
      ),
      const AppDialogAction<UpdateChoice>(
        label: '取消',
        result: UpdateChoice.later,
      ),
      const AppDialogAction<UpdateChoice>(
        label: '跳过此版本',
        result: UpdateChoice.skip,
      ),
    ],
  );
}

/// 下载 APK -> 拉起系统安装器；全程自带进度弹窗。
Future<void> installRelease({
  required BuildContext context,
  required WidgetRef ref,
  required ReleaseInfo release,
}) async {
  final repository = ref.read(updateRepositoryProvider);
  // atom 兜底没有附件信息：先按 tag 读一次 assets 面板，确认能装再下载。
  final asset = await repository.resolveApk(release);
  if (!context.mounted) return;
  if (asset == null) {
    final opened = await repository.openReleasePage(release);
    if (!context.mounted) return;
    AppToast.show(
      context,
      opened ? '没找到 APK 附件，已打开发布页' : '没找到 APK 附件，请到发布页手动下载',
      duration: const Duration(seconds: 4),
    );
    return;
  }

  final outcome = await _showDownloadDialog(
    context: context,
    repository: repository,
    release: release,
    asset: asset,
  );
  if (!context.mounted) return;
  final path = outcome.path;
  if (path == null) {
    final error = outcome.error;
    if (error != null) {
      AppToast.show(
        context,
        '下载失败：$error',
        duration: const Duration(seconds: 5),
      );
    }
    return;
  }

  final launched = await repository.installApk(path);
  if (!context.mounted) return;
  if (launched) {
    AppToast.show(context, '已启动安装器，按提示完成安装');
    return;
  }
  // 安装器拉不起来（常见于未授予「安装未知来源应用」）：退回发布页。
  await repository.openReleasePage(release);
  if (!context.mounted) return;
  AppToast.show(
    context,
    '安装包已下载，但没能拉起安装器；已打开发布页',
    duration: const Duration(seconds: 5),
  );
}

// ---------------------------------------------------------------------------
// 弹窗内容
// ---------------------------------------------------------------------------

/// 版本行 + release 页 readme。
class _ReleasePanel extends StatelessWidget {
  const _ReleasePanel({required this.release, required this.current});

  final ReleaseInfo release;
  final AppVersion current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxNotesHeight =
        (MediaQuery.sizeOf(context).height * 0.40).clamp(150.0, 420.0);
    final apk = release.apk;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          release.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            ReleaseVersionBadge(
              label: release.versionLabel,
              highlighted: true,
            ),
            ReleaseVersionBadge(label: '当前 ${current.display}'),
            if (release.publishedLabel.isNotEmpty)
              ReleaseVersionBadge(label: release.publishedLabel),
            if (apk != null && apk.sizeText.isNotEmpty)
              ReleaseVersionBadge(label: apk.sizeText),
          ],
        ),
        const SizedBox(height: 12),
        Container(height: 1, color: scheme.outlineVariant),
        const SizedBox(height: 10),
        ReleaseNotesView(
          notes: release.notes,
          maxHeight: maxNotesHeight,
          emptyHint: '该版本没有写发布说明，点「安装」直接下载最新安装包',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 下载进度弹窗
// ---------------------------------------------------------------------------

/// 下载结果：成功带本地路径，失败带原因，取消两者都为空。
class _DownloadOutcome {
  const _DownloadOutcome.cancelled()
      : path = null,
        error = null;

  const _DownloadOutcome.completed(String this.path) : error = null;

  const _DownloadOutcome.failed(String this.error) : path = null;

  final String? path;
  final String? error;
}

Future<_DownloadOutcome> _showDownloadDialog({
  required BuildContext context,
  required UpdateRepository repository,
  required ReleaseInfo release,
  required ReleaseAsset asset,
}) async {
  var outcome = const _DownloadOutcome.cancelled();
  final body = _UpdateDownloadBody(
    repository: repository,
    release: release,
    asset: asset,
    onResult: (value) => outcome = value,
  );

  if (!context.isLiquidGlass) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('下载更新 ${release.versionLabel}'),
        content: SizedBox(width: 300, child: body),
      ),
    );
    return outcome;
  }

  final materialTheme = Theme.of(context);
  final tokens = AppGlassTheme.of(context);
  BuildContext? dialogContext;
  await GlassDialog.show<void>(
    context: context,
    title: '下载更新 ${release.versionLabel}',
    settings: tokens.overlay,
    quality: AppGlassTheme.overlayQuality,
    barrierDismissible: false,
    content: Builder(
      builder: (context) {
        dialogContext = context;
        return Theme(
          data: materialTheme,
          child: InheritedGlassSurfaceStyle(
            surfaceStyle: GlassSurfaceStyle.solid,
            child: Material(
              type: MaterialType.transparency,
              child: body,
            ),
          ),
        );
      },
    ),
    actions: <GlassDialogAction>[
      GlassDialogAction(
        label: '取消下载',
        onPressed: () {
          final ctx = dialogContext;
          if (ctx != null && ctx.mounted) Navigator.of(ctx).pop();
        },
      ),
    ],
  );
  return outcome;
}

/// 下载中：进度条 + 已下载量 + 取消按钮（两套主题渲染同一份内容）。
class _UpdateDownloadBody extends StatefulWidget {
  const _UpdateDownloadBody({
    required this.repository,
    required this.release,
    required this.asset,
    required this.onResult,
  });

  final UpdateRepository repository;
  final ReleaseInfo release;
  final ReleaseAsset asset;
  final ValueChanged<_DownloadOutcome> onResult;

  @override
  State<_UpdateDownloadBody> createState() => _UpdateDownloadBodyState();
}

class _UpdateDownloadBodyState extends State<_UpdateDownloadBody> {
  final CancelToken _token = CancelToken();
  double? _progress;
  String _status = '正在连接 GitHub…';
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    // 用户中途关掉弹窗：取消正在跑的下载，别让 dio 继续吃流量。
    if (!_token.isCancelled) _token.cancel('对话框已关闭');
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final path = await widget.repository.downloadApk(
        widget.release,
        asset: widget.asset,
        cancelToken: _token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
            _status = total > 0
                ? '已下载 ${_mb(received)} / ${_mb(total)}'
                : '已下载 ${_mb(received)}';
          });
        },
      );
      if (!mounted) return;
      _finished = true;
      widget.onResult(_DownloadOutcome.completed(path));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      _finished = true;
      final message = error is ReleaseDownloadException
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      widget.onResult(_DownloadOutcome.failed(message));
      Navigator.of(context).pop();
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppProgressIndicator.linear(
          value: _progress,
          minHeight: 4,
          semanticsLabel: '更新包下载进度',
          semanticsValue:
              _progress == null ? null : '${(_progress! * 100).round()}%',
        ),
        const SizedBox(height: 10),
        Text(
          _status,
          style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton.text(
            onPressed: () {
              if (_finished) return;
              _token.cancel('用户取消');
              widget.onResult(const _DownloadOutcome.cancelled());
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              textStyle: AppTypography.caption,
              minimumSize: const Size(0, 32),
            ),
            child: const Text('取消下载'),
          ),
        ),
      ],
    );
  }
}
