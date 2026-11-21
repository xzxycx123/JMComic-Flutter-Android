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
              child: DownloadFilterBar(
                selected: filter,
                activeCount: activeCount,
                onChanged: (value) {
                  ref.read(downloadFilterProvider.notifier).state = value;
                },
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

/// 下载页分段筛选条：全部 / 进行中 / 已完成。
///
/// 玻璃壳只包住分段本身（导航与控制层），不改变 LiquidGlass 观感。三个分段等宽、
/// 文案居中铺满可用宽度；可用宽度不足（窄屏 + 大字号）时整条横向可滑动，
/// 每个分段至少保留 [minCellWidth]（按字号缩放）。
class DownloadFilterBar extends StatelessWidget {
  const DownloadFilterBar({
    required this.selected,
    required this.onChanged,
    super.key,
    this.activeCount = 0,
  });

  final DownloadFilter selected;
  final ValueChanged<DownloadFilter> onChanged;

  /// 「进行中」后面的任务数（>0 才拼进文案）。
  final int activeCount;

  /// 单个分段的最小宽度（逻辑像素，实际会按 textScaler 放大）。
  static const double minCellWidth = 96;

  /// 分段文案（数量只在「进行中」且有任务时出现）。
  static String labelOf(DownloadFilter filter, {int activeCount = 0}) =>
      filter == DownloadFilter.active && activeCount > 0
          ? '${filter.label} $activeCount'
          : filter.label;

  /// 筛选条需要的最小总宽度（按当前字号缩放）。
  static double minWidthFor(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(minCellWidth) *
      DownloadFilter.values.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <AppSegment<DownloadFilter>>[
      for (final filter in DownloadFilter.values)
        AppSegment<DownloadFilter>(
          value: filter,
          label: Text(labelOf(filter, activeCount: activeCount)),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final needed = minWidthFor(context);
        // 宽度够就撑满可用宽度（三个等宽分段居中）；不够则锁最小宽度并横向滑动。
        final width =
            available.isFinite && available > needed ? available : needed;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: width,
            child: AppSegmentedControl<DownloadFilter>(
              segments: segments,
              selected: selected,
              // 固定模式（等宽分段）才是「居中」的；滑动由外层承担。
              onChanged: onChanged,
              metalStyle: SegmentedButton.styleFrom(
                textStyle: AppTypography.caption,
                side: BorderSide(color: scheme.outline),
                selectedBackgroundColor: scheme.primaryContainer,
                selectedForegroundColor: scheme.onPrimaryContainer,
              ),
            ),
          ),
        );
      },
    );
  }
}
