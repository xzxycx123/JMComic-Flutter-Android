import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../icons/app_icons.dart';
import '../../theme/app_glass_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/interface_style_scope.dart';

enum AppChipKind { staticLabel, action, choice, input }

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.leading,
    this.onTap,
    this.onDeleted,
    this.selected = false,
    this.enabled = true,
    this.color,
    this.foregroundColor,
    this.padding,
    this.semanticLabel,
    this.metalChild,
    this.kind = AppChipKind.staticLabel,
  });

  final Widget label;
  final Widget? leading;
  final VoidCallback? onTap;
  final VoidCallback? onDeleted;
  final bool selected;
  final bool enabled;
  final Color? color;
  final Color? foregroundColor;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;
  final Widget? metalChild;
  final AppChipKind kind;

  static const _delete = SvgIcon(AppIcons.close, size: 16);

  @override
  Widget build(BuildContext context) {
    if (!context.isLiquidGlass) return metalChild ?? _buildMetal();

    final tokens = AppGlassTheme.of(context);
    final ink =
        foregroundColor ?? (selected ? tokens.accent : tokens.scheme.onSurface);
    final text = label is Text ? label as Text : null;
    final plain = text?.data ?? text?.textSpan?.toPlainText();
    final inset =
        padding ?? const EdgeInsets.symmetric(horizontal: 11, vertical: 7);
    final settings = tokens.control(
      tint: selected ? tokens.scheme.primary : color,
      enabled: enabled,
    );
    // GlassChip takes a string. Keep custom child widgets visible (and their
    // own semantics intact) by adapting them to the chip's content slot.
    return GlassChip(
      label: plain ?? '',
      icon: plain != null
          ? leading
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                Flexible(child: label),
              ],
            ),
      spacing: plain == null ? 0 : 6,
      semanticLabel: semanticLabel ?? text?.semanticsLabel,
      deleteSemanticLabel: '移除${semanticLabel ?? plain ?? '标签'}',
      iconColor: ink,
      labelStyle: AppTypography.caption.merge(text?.style).copyWith(
            color: ink,
            fontWeight: selected ? FontWeight.w600 : text?.style?.fontWeight,
          ),
      selected: selected,
      selectedColor: tokens.selection,
      enabled: enabled,
      onTap: onTap,
      onDeleted: onDeleted,
      deleteIcon: _delete,
      padding: inset,
      settings: settings,
      quality: AppGlassTheme.scrollQuality,
      surfaceStyle: GlassSurfaceStyle.glass,
      interactionScale: tokens.reduceMotion ? 1 : .97,
      anchorStretch: !tokens.reduceMotion,
      stretch: tokens.reduceMotion ? 0 : .12,
      glowRadius: tokens.reduceMotion ? 0 : .65,
    );
  }

  Widget _buildMetal() {
    final VoidCallback? tap = enabled ? onTap : null;
    final VoidCallback? delete = enabled ? onDeleted : null;
    final effectiveKind =
        kind == AppChipKind.staticLabel && (onTap != null || onDeleted != null)
            ? (onDeleted == null ? AppChipKind.action : AppChipKind.input)
            : kind;
    final labelStyle =
        foregroundColor == null ? null : TextStyle(color: foregroundColor);
    return switch (effectiveKind) {
      AppChipKind.staticLabel => Chip(
          label: label,
          avatar: leading,
          backgroundColor: color,
          labelStyle: labelStyle,
          padding: padding,
        ),
      AppChipKind.action => ActionChip(
          label: label,
          avatar: leading,
          backgroundColor: color,
          labelStyle: labelStyle,
          padding: padding,
          onPressed: tap,
        ),
      AppChipKind.choice => ChoiceChip(
          label: label,
          avatar: leading,
          backgroundColor: color,
          labelStyle: labelStyle,
          padding: padding,
          selected: selected,
          onSelected: tap == null ? null : (_) => tap(),
        ),
      AppChipKind.input => InputChip(
          label: label,
          avatar: leading,
          backgroundColor: color,
          labelStyle: labelStyle,
          padding: padding,
          selected: selected,
          isEnabled: enabled,
          onPressed: tap,
          onDeleted: delete,
          deleteIcon: _delete,
        ),
    };
  }
}
