import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.constraints,
    this.padding,
    this.iconSize,
    this.style,
    this.selected = false,
    this.focusNode,
    this.autofocus = false,
    this.glassSize = 44,
    this.glassTransparent = false,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry? padding;
  final double? iconSize;
  final ButtonStyle? style;
  final bool selected;
  final FocusNode? focusNode;
  final bool autofocus;
  final double glassSize;
  final bool glassTransparent;

  @override
  Widget build(BuildContext context) {
    if (!context.isLiquidGlass) {
      return IconButton(
        icon: icon,
        onPressed: onPressed,
        tooltip: tooltip,
        color: color,
        constraints: constraints,
        padding: padding,
        iconSize: iconSize,
        style: style,
        focusNode: focusNode,
        autofocus: autofocus,
      );
    }
    final tokens = AppGlassTheme.of(context);
    final button = GlassIconButton(
      icon: icon,
      size: glassSize,
      iconSize: iconSize,
      iconColor: color ?? (selected ? tokens.accent : tokens.scheme.onSurface),
      onPressed: onPressed,
      semanticLabel: tooltip,
      settings: tokens.control(
        tint: selected ? tokens.scheme.primary : null,
        enabled: onPressed != null,
      ),
      quality: AppGlassTheme.controlQuality,
      style: glassTransparent
          ? GlassButtonStyle.transparent
          : GlassButtonStyle.filled,
      surfaceStyle: GlassSurfaceStyle.glass,
      focusNode: focusNode,
      autofocus: autofocus,
      interactionScale: tokens.reduceMotion ? 1 : .95,
      anchorStretch: !tokens.reduceMotion,
      glowRadius: tokens.reduceMotion ? 0 : 1.2,
    );
    return tooltip == null
        ? button
        : Tooltip(
            message: tooltip!,
            excludeFromSemantics: true,
            child: button,
          );
  }
}
