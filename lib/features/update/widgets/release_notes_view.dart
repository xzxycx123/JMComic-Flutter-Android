import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/models/release_notes.dart';

/// 把 release 页的 readme（[ReleaseNotes] 的 block 列表）排成可滚动正文。
///
/// 两套皮肤共用：颜色全部取自 `Theme.of(context).colorScheme`，
/// LiquidGlass 弹窗内部会被包进 `GlassSurfaceStyle.solid`，所以这里不需要玻璃层。
class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({
    super.key,
    required this.notes,
    this.maxHeight,
    this.emptyHint = '该版本没有写发布说明',
  });

  final ReleaseNotes notes;

  /// 超出后内部滚动（弹窗里用，避免撑爆屏幕）。
  final double? maxHeight;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = notes.isEmpty
        ? Text(
            emptyHint,
            style: AppTypography.body.copyWith(color: scheme.onSurfaceVariant),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final block in notes.blocks) _block(context, block),
            ],
          );
    if (maxHeight == null) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight!),
      child: SingleChildScrollView(
        primary: false,
        child: content,
      ),
    );
  }

  Widget _block(BuildContext context, ReleaseNoteBlock block) {
    final scheme = Theme.of(context).colorScheme;
    switch (block.kind) {
      case ReleaseNoteKind.heading:
        final first = block.level <= 1;
        return Padding(
          padding: EdgeInsets.only(top: first ? 2 : 12, bottom: 6),
          child: Text(
            block.text,
            style:
                (first ? AppTypography.sectionTitle : AppTypography.bodyStrong)
                    .copyWith(color: scheme.onSurface),
          ),
        );
      case ReleaseNoteKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            block.text,
            style: AppTypography.body.copyWith(color: scheme.onSurface),
          ),
        );
      case ReleaseNoteKind.bullet:
        return _listRow(context, marker: null, text: block.text);
      case ReleaseNoteKind.ordered:
        return _listRow(
          context,
          marker: '${block.index}.',
          text: block.text,
        );
      case ReleaseNoteKind.quote:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.only(left: 10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: scheme.primary.withValues(alpha: .55),
                  width: 3,
                ),
              ),
            ),
            child: Text(
              block.text,
              style: AppTypography.caption.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
        );
      case ReleaseNoteKind.code:
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              block.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      case ReleaseNoteKind.divider:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Container(
            height: 1,
            color: scheme.outlineVariant,
          ),
        );
    }
  }

  Widget _listRow(
    BuildContext context, {
    required String? marker,
    required String text,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: marker == null ? 14 : 22,
            child: marker == null
                // 项目符号用自绘小圆点，避免往代码里塞装饰字符。
                ? Padding(
                    padding: const EdgeInsets.only(top: 7, left: 2),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : Text(
                    marker,
                    style: AppTypography.body.copyWith(color: scheme.primary),
                  ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTypography.body.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「v0.4.4 · 2026-11-22 · 当前 v0.4.3」这一行的胶囊标签。
class ReleaseVersionBadge extends StatelessWidget {
  const ReleaseVersionBadge({
    super.key,
    required this.label,
    this.highlighted = false,
  });

  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
            highlighted ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppColors.radiusPill),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        maxLines: 1,
        style: AppTypography.micro.copyWith(
          color:
              highlighted ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
