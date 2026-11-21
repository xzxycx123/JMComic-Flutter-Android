import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../../core/icons/app_icons.dart';
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
    this.autofocus = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onCancel;
  final FocusNode? focusNode;
  final bool autofocus;
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
              autofocus: autofocus,
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

/// 历史关键词保留普通点击；长按或右键才打开单条操作菜单。
class _HistoryEntry extends StatefulWidget {
  const _HistoryEntry(
      {super.key, required this.keyword, required this.onTap, this.onRemove,});

  final String keyword;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  State<_HistoryEntry> createState() => _HistoryEntryState();
}

class _HistoryEntryState extends State<_HistoryEntry> {
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    if (_menuOpen || widget.onRemove == null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    final anchor = context.findRenderObject();
    final overlay = navigator.overlay?.context.findRenderObject();
    if (anchor is! RenderBox || overlay is! RenderBox || !anchor.hasSize) {
      return;
    }
    final tokens = AppGlassTheme.of(context);
    _menuOpen = true;
    try {
      if (context.isLiquidGlass) {
        await showGlassContextMenu<void>(
          context: context,
          targetRect: anchor.localToGlobal(Offset.zero) & anchor.size,
          rowBorderRadius: 10,
          menuWidth: 180,
          settings: tokens.overlay,
          quality: AppGlassTheme.overlayQuality,
          previewBuilder: (_) => Center(
            child: Text(
              widget.keyword,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption
                  .copyWith(color: tokens.scheme.onSurface),
            ),
          ),
          // Open the platter without glide-to-select; release alone never deletes.
          actions: [
            GlassContextMenuAction(
              isDestructive: true,
              icon: const SvgIcon(AppIcons.trash, size: 18),
              onPressed: () {
                if (mounted) widget.onRemove?.call();
              },
              child: const Text('删除'),
            ),
          ],
        );
      } else {
        final rect =
            anchor.localToGlobal(Offset.zero, ancestor: overlay) & anchor.size;
        final selected = await showMenu<bool>(
          context: context,
          useRootNavigator: true,
          position: RelativeRect.fromSize(rect, overlay.size),
          items: [
            PopupMenuItem<bool>(
              value: true,
              child: Row(
                children: [
                  SvgIcon(AppIcons.trash, size: 18, color: tokens.scheme.error),
                  const SizedBox(width: 10),
                  Text('删除', style: TextStyle(color: tokens.scheme.error)),
                ],
              ),
            ),
          ],
        );
        if (mounted && selected == true) widget.onRemove?.call();
      }
    } finally {
      _menuOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final openMenu =
        widget.onRemove == null ? null : () => unawaited(_openMenu());
    return GestureDetector(
      onLongPress: openMenu,
      onSecondaryTap: openMenu,
      child: AppChip(
        kind: AppChipKind.action,
        cornerRadius: 10,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        onTap: widget.onTap,
        label:
            Text(widget.keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
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
          children: [
            for (final keyword in history)
              _HistoryEntry(
                key: ValueKey(keyword),
                keyword: keyword,
                onTap: () => onSelect(keyword),
                onRemove: onRemove == null ? null : () => onRemove!(keyword),
              ),
          ],
        ),
      ],
    );
  }
}
