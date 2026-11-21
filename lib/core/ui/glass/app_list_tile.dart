import 'package:flutter/material.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

/// Shares the platform tile's layout and focus behavior. In Glass mode the
/// row uses a non-refracting selection fill so its trailing control owns its lens.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.isThreeLine,
    this.dense,
    this.visualDensity,
    this.shape,
    this.style,
    this.selectedColor,
    this.iconColor,
    this.textColor,
    this.titleTextStyle,
    this.subtitleTextStyle,
    this.leadingAndTrailingTextStyle,
    this.contentPadding,
    this.enabled = true,
    this.onTap,
    this.onLongPress,
    this.onFocusChange,
    this.mouseCursor,
    this.selected = false,
    this.focusColor,
    this.hoverColor,
    this.splashColor,
    this.focusNode,
    this.autofocus = false,
    this.tileColor,
    this.selectedTileColor,
    this.enableFeedback,
    this.horizontalTitleGap,
    this.minVerticalPadding,
    this.minLeadingWidth,
    this.minTileHeight,
    this.titleAlignment,
  });

  final Widget? leading, title, subtitle, trailing;
  final bool? isThreeLine, dense, enableFeedback;
  final bool enabled, selected, autofocus;
  final VisualDensity? visualDensity;
  final ShapeBorder? shape;
  final ListTileStyle? style;
  final Color? selectedColor,
      iconColor,
      textColor,
      focusColor,
      hoverColor,
      splashColor,
      tileColor,
      selectedTileColor;
  final TextStyle? titleTextStyle,
      subtitleTextStyle,
      leadingAndTrailingTextStyle;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap, onLongPress;
  final ValueChanged<bool>? onFocusChange;
  final MouseCursor? mouseCursor;
  final FocusNode? focusNode;
  final double? horizontalTitleGap,
      minVerticalPadding,
      minLeadingWidth,
      minTileHeight;
  final ListTileTitleAlignment? titleAlignment;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass ? AppGlassTheme.of(context) : null;
    final tile = ListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      isThreeLine: isThreeLine,
      dense: dense,
      visualDensity: visualDensity,
      shape: shape ??
          (glass == null
              ? null
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),)),
      style: style,
      selectedColor: selectedColor ?? glass?.accent,
      iconColor: iconColor,
      textColor: textColor,
      titleTextStyle: titleTextStyle,
      subtitleTextStyle: subtitleTextStyle,
      leadingAndTrailingTextStyle: leadingAndTrailingTextStyle,
      contentPadding: contentPadding,
      enabled: enabled,
      onTap: onTap,
      onLongPress: onLongPress,
      onFocusChange: onFocusChange,
      mouseCursor: mouseCursor,
      selected: selected,
      focusColor: focusColor ?? glass?.selection,
      hoverColor: hoverColor ?? glass?.scheme.onSurface.withValues(alpha: .06),
      splashColor: splashColor ?? glass?.selection,
      focusNode: focusNode,
      autofocus: autofocus,
      tileColor: tileColor,
      selectedTileColor: selectedTileColor ?? glass?.selection,
      enableFeedback: enableFeedback,
      horizontalTitleGap: horizontalTitleGap,
      minVerticalPadding: minVerticalPadding,
      minLeadingWidth: minLeadingWidth,
      minTileHeight: minTileHeight,
      titleAlignment: titleAlignment,
    );
    return glass == null
        ? tile
        : Material(type: MaterialType.transparency, child: tile);
  }
}
