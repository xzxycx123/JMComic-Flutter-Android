import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/providers.dart';
import '../../core/icons/app_icons.dart';
import '../../core/icons/app_images.dart';
import '../../core/theme/app_typography.dart';
import '../../core/ui/glass/app_glass.dart';
import '../../data/models/download_record.dart';
import '../home/widgets/feed_skeleton.dart';
import '../pdf/pdf_viewer_page.dart';
import 'download_providers.dart';
import 'widgets/task_card.dart';

/// 历史记录：从「我的」二级菜单进入，按状态筛选已结束的下载任务。
enum HistoryFilter {
  all('全部'),
  succeeded('已完成'),
  failed('失败'),
  cancelled('已取消');

  const HistoryFilter(this.label);

  final String label;

  bool matches(DownloadRecord record) => switch (this) {
        HistoryFilter.all => record.isFinished,
        HistoryFilter.succeeded => record.state == DownloadState.succeeded,
        HistoryFilter.failed => record.state == DownloadState.failed,
        HistoryFilter.cancelled => record.state == DownloadState.cancelled,
      };
}

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  HistoryFilter _filter = HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final repository = ref.watch(downloadRepositoryProvider);
    final all = ref.watch(downloadRecordsProvider);
    final finished =
        all.where((record) => record.isFinished).toList(growable: false);
    final records = finished.where(_filter.matches).toList(growable: false);

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
        title: const Text('历史记录'),
        actions: <Widget>[
          if (finished.isNotEmpty)
            AppButton.text(
              onPressed: _confirmClear,
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
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: AppSegmentedControl<HistoryFilter>(
                    segments: <AppSegment<HistoryFilter>>[
                      for (final filter in HistoryFilter.values)
                        AppSegment<HistoryFilter>(
                          value: filter,
                          label: Text(
                            filter == HistoryFilter.all
                                ? '${filter.label} ${finished.length}'
                                : filter.label,
                          ),
                        ),
                    ],
                    selected: _filter,
                    scrollable: true,
                    onChanged: (filter) => setState(() => _filter = filter),
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
          Expanded(
            child: records.isEmpty
                ? EmptyState(
                    imageAsset: AppImages.rocket,
                    title:
                        _filter == HistoryFilter.all ? '还没有下载记录' : '这个筛选下没有记录',
                    description: '输入车号，完成的本子会归档到 Documents/JMComics/',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: records.length,
                    itemBuilder: (context, index) {
                      final record = records[index];
                      return TaskCard(
                        record: record,
                        onOpen: () {
                          final uri = record.openUri;
                          if (uri == null) return;
                          context.push(
                            PdfViewerArgs(
                              uri: uri,
                              title: record.displayTitle,
                            ).route,
                          );
                        },
                        onCancel: () => repository.cancel(record.workId),
                        onRetry: () => repository.retry(record.workId),
                        onRemove: () => repository.remove(record.workId),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear() async {
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

/// 供「我的」页展示的历史摘要。
String historySummary(List<DownloadRecord> records) {
  final succeeded =
      records.where((record) => record.state == DownloadState.succeeded).length;
  final failed =
      records.where((record) => record.state == DownloadState.failed).length;
  if (records.isEmpty) return '';
  return '完成 $succeeded · 失败 $failed';
}
