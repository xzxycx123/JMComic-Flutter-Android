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
    this.glassSize,
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
  final double? glassSize;
  final bool glassTransparent;

  @override
  Widget build(BuildContext context) {
    final isBack = tooltip == '返回';
    final displayIcon = isBack
        ? SizedBox.square(dimension: 18, child: FittedBox(child: icon))
        : icon;
    if (!context.isLiquidGlass) {
      return IconButton(
        icon: displayIcon,
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
    final size = glassSize ?? (isBack ? 34.0 : 44.0);
    final button = GlassIconButton(
      icon: displayIcon,
      size: size,
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
      surfaceStyle: glassTransparent ? GlassSurfaceStyle.solid : null,
      focusNode: focusNode,
      autofocus: autofocus,
      interactionScale: tokens.reduceMotion ? 1 : .95,
      anchorStretch: !tokens.reduceMotion,
      glowRadius: tokens.reduceMotion ? 0 : 1.2,
    );
    final target = isBack && size < 44
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onPressed,
            child: SizedBox.square(dimension: 44, child: Center(child: button)),
          )
        : button;
    return tooltip == null
        ? target
        : Tooltip(
            message: tooltip!,
            excludeFromSemantics: true,
            child: target,
          );
  }
}
