import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/app_toast.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../core/utils/jm_id_parser.dart';
import '../../data/models/download_record.dart';
import '../home/widgets/feed_skeleton.dart';
import '../pdf/pdf_viewer_page.dart';
import 'download_providers.dart';
import 'widgets/download_input.dart';
import 'widgets/task_card.dart';

/// 下载页：批量输入 + 队列 + 分段筛选 + 任务操作。
class DownloadPage extends ConsumerStatefulWidget {
  const DownloadPage({super.key});

  @override
  ConsumerState<DownloadPage> createState() => _DownloadPageState();
}

class _DownloadPageState extends ConsumerState<DownloadPage> {
  late final TextEditingController _controller =
      TextEditingController(text: ref.read(downloadInputProvider));
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final preview = previewJmIds(_controller.text);
    const duration = Duration(seconds: 4);
    if (preview.isEmpty) {
      AppToast.show(context, '没有识别到有效车号', duration: duration);
      return;
    }

    setState(() => _busy = true);
    try {
      final repository = ref.read(downloadRepositoryProvider);
      final result = await repository.enqueueInput(_controller.text);
      if (!mounted) return;
      _controller.clear();
      ref.read(downloadInputProvider.notifier).state = '';
      final parts = <String>['已加入 ${result.added} 个任务'];
      if (result.skipped > 0) {
        parts.add('${result.skipped} 个已在队列中');
      }
      AppToast.show(context, parts.join(' · '), duration: duration);
    } catch (error) {
      if (!mounted) return;
      AppToast.show(context, '加入队列失败：$error', duration: duration);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filter = ref.watch(downloadFilterProvider);
    final records = ref.watch(filteredRecordsProvider);
    final allRecords = ref.watch(downloadRecordsProvider);
    final activeCount = ref.watch(activeDownloadCountProvider);
    final repository = ref.watch(downloadRepositoryProvider);

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
        title: const Text('下载'),
        actions: <Widget>[
          if (allRecords.any((record) => record.isFinished))
            AppButton.text(
              onPressed: _clearFinished,
              foregroundColor: scheme.onSurfaceVariant,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                textStyle: AppTypography.caption,
              ),
              child: const Text('清空已完成'),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: DownloadInput(
                controller: _controller,
                busy: _busy,
                onSubmit: _submit,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: AppSegmentedControl<DownloadFilter>(
                      segments: <AppSegment<DownloadFilter>>[
                        AppSegment<DownloadFilter>(
                          value: DownloadFilter.all,
                          label: Text(DownloadFilter.all.label),
                        ),
                        AppSegment<DownloadFilter>(
                          value: DownloadFilter.active,
                          label: Text(
                            activeCount > 0
                                ? '${DownloadFilter.active.label} $activeCount'
                                : DownloadFilter.active.label,
                          ),
                        ),
                        AppSegment<DownloadFilter>(
                          value: DownloadFilter.finished,
                          label: Text(DownloadFilter.finished.label),
                        ),
                      ],
                      selected: filter,
                      scrollable: true,
                      onChanged: (value) {
                        ref.read(downloadFilterProvider.notifier).state = value;
                      },
                      metalStyle: SegmentedButton.styleFrom(
                        textStyle: AppTypography.caption,
                        side: BorderSide(color: scheme.outline),
                        selectedBackgroundColor: scheme.primaryContainer,
                        selectedForegroundColor: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: records.isEmpty
                  ? EmptyState(
                      imageAsset: AppImages.rocket,
                      title: filter == DownloadFilter.all
                          ? '输入车号开始下载'
                          : '这个分组还没有任务',
                      description: '车号可从本子链接 /album/[JMCODE]/ 中获取',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      itemCount: records.length,
                      itemBuilder: (context, index) {
                        final record = records[index];
                        return TaskCard(
                          record: record,
                          onOpen: () => _openPdf(context, record),
                          onCancel: () => repository.cancel(record.workId),
                          onRetry: () => repository.retry(record.workId),
                          onRemove: () => repository.remove(record.workId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开本地 PDF：优先用内置阅读器（PdfRenderer），打不开再退回系统应用。
  void _openPdf(BuildContext context, DownloadRecord record) {
    final uri = record.openUri;
    if (uri == null) {
      AppToast.show(
        context,
        '这个任务还没有生成 PDF 文件',
        duration: const Duration(seconds: 4),
      );
      return;
    }
    context.push(PdfViewerArgs(uri: uri, title: record.displayTitle).route);
  }

  Future<void> _clearFinished() async {
    final confirmed = await AppDialog.show<bool>(
      context: context,
      title: '清空已完成',
      message: '只清理记录，已导出的 PDF 不受影响。',
      actions: const <AppDialogAction<bool>>[
        AppDialogAction<bool>(label: '取消', result: false),
        AppDialogAction<bool>(
          label: '清空',
          result: true,
          primary: true,
          destructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;
    await ref.read(downloadRepositoryProvider).clearFinished();
  }
}

/// 供测试 / 其它页面复用的记录状态文案。
String describeRecord(DownloadRecord record) =>
    record.state == DownloadState.succeeded
        ? '${record.pageCount} 页 · ${record.pdfName ?? '已导出'}'
        : '${record.status} ${record.percent}%';
