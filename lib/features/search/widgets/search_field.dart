import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';

/// 搜索框：高 44、圆角 999、前缀 search 图标、右侧清空 + 取消。
class SearchField extends StatelessWidget {
  const SearchField({
    required this.controller,
    required this.onSubmitted,
    required this.onCancel,
    super.key,
    this.focusNode,
    this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Expanded(
          child: SizedBox(
            height: 44,
            child: AppSearchBar(
              controller: controller,
              focusNode: focusNode,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              style: AppTypography.body.copyWith(color: scheme.onSurface),
              decoration: InputDecoration(
                isDense: true,
                hintText: '车号 or 关键词',
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 40, minHeight: 40),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: const SvgIcon(AppIcons.search, size: 18),
                  ),
                ),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, child) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return AppIconButton(
                      glassTransparent: true,
                      glassSize: 36,
                      tooltip: '清空搜索',
                      icon: IconTheme(
                        data: IconThemeData(color: scheme.onSurfaceVariant),
                        child: const SvgIcon(AppIcons.close, size: 16),
                      ),
                      onPressed: () {
                        controller.clear();
                        onChanged?.call('');
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton.text(
          onPressed: onCancel,
          style: TextButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle: AppTypography.bodyStrong,
          ),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

/// 历史 chip 行（最多 10 条 + 清空）。
class HistoryChips extends StatelessWidget {
  const HistoryChips({
    required this.history,
    required this.onSelect,
    required this.onClear,
    this.onRemove,
    super.key,
  });

  final List<String> history;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;
  final ValueChanged<String>? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (history.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              '搜索历史',
              style: AppTypography.bodyStrong.copyWith(color: scheme.onSurface),
            ),
            const Spacer(),
            AppButton.text(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                minimumSize: const Size(0, 32),
                textStyle: AppTypography.caption,
              ),
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: history.map((keyword) {
            void select() => onSelect(keyword);
            final label = Text(keyword);
            final remove = onRemove;
            return AppChip(
              label: Text(keyword, style: AppTypography.caption),
              onTap: select,
              onDeleted: remove == null ? null : () => remove(keyword),
              kind: AppChipKind.input,
              metalChild: ActionChip(
                label: label,
                onPressed: select,
                labelStyle:
                    AppTypography.caption.copyWith(color: scheme.onSurface),
                backgroundColor: scheme.surfaceContainer,
                side: BorderSide(color: scheme.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppColors.radiusPill),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}
