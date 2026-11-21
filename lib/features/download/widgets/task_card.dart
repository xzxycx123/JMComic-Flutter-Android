import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../../../data/models/download_record.dart';
import '../../home/widgets/cover_image.dart';

/// 任务卡：封面缩略 + 标题 + 状态胶囊 + 环形进度 + 操作菜单。
///
/// 任务列表属于滚动内容 / 密集列表：整卡用 solid 实色表面，不放玻璃。
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.record,
    super.key,
    this.onOpen,
    this.onCancel,
    this.onRetry,
    this.onRemove,
  });

  final DownloadRecord record;
  final VoidCallback? onOpen;
  final VoidCallback? onCancel;
  final VoidCallback? onRetry;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = record.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 48,
            height: 64,
            child: CoverImage(
              albumId: record.albumId,
              radius: 8,
              showPlaceholderIcon: false,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        record.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle
                            .copyWith(color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatePill(state: record.state),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _statusLine(record),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.micro
                      .copyWith(color: scheme.onSurfaceVariant),
                ),
                if (record.error != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    record.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.micro.copyWith(color: scheme.error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: <Widget>[
              if (active)
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      AppProgressIndicator.circular(
                        size: 34,
                        value:
                            record.percent <= 0 ? null : record.percent / 100,
                        strokeWidth: 2.4,
                      ),
                      Text(
                        '${record.percent}',
                        style: AppTypography.micro
                            .copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                )
              else
                AppMenu<String>(
                  icon: IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.settings, size: 18),
                  ),
                  onSelected: (value) {
                    switch (value) {
                      case 'open':
                        onOpen?.call();
                        break;
                      case 'retry':
                        onRetry?.call();
                        break;
                      case 'remove':
                        onRemove?.call();
                        break;
                    }
                  },
                  items: <AppMenuItem<String>>[
                    if (record.isOpenable)
                      const AppMenuItem<String>(value: 'open', label: '打开 PDF'),
                    if (record.state == DownloadState.failed ||
                        record.state == DownloadState.cancelled)
                      const AppMenuItem<String>(value: 'retry', label: '重试'),
                    const AppMenuItem<String>(
                      value: 'remove',
                      label: '删除记录',
                      destructive: true,
                    ),
                  ],
                ),
              if (active)
                AppIconButton(
                  tooltip: '取消',
                  onPressed: onCancel,
                  icon: IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.close, size: 16),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(DownloadRecord record) {
    if (record.state == DownloadState.succeeded) {
      final name = record.pdfName ?? '导出完成';
      return '${record.pageCount} 页 · $name';
    }
    if (record.total > 0) {
      return '${record.status} · ${record.done}/${record.total} 页';
    }
    return record.status;
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.state});

  final DownloadState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      DownloadState.succeeded => scheme.primary,
      DownloadState.failed => scheme.error,
      DownloadState.cancelled => scheme.onSurfaceVariant,
      _ => scheme.secondary,
    };
    const padding = EdgeInsets.symmetric(horizontal: 8, vertical: 3);
    final label = Text(
      state.label,
      style: AppTypography.micro.copyWith(color: color),
    );
    return AppChip(
      kind: AppChipKind.staticLabel,
      label: label,
      padding: padding,
      color: color.withValues(alpha: 0.14),
      foregroundColor: color,
      metalChild: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
        ),
        child: label,
      ),
    );
  }
}
