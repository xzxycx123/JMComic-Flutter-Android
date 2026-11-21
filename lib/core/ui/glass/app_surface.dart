import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

enum AppSurfaceKind { content, controlGroup, overlay }

class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.kind = AppSurfaceKind.content,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    this.metalDecoration,
    this.onTap,
    this.onLongPress,
    this.metalChild,
  });

  final Widget child;
  final AppSurfaceKind kind;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final BoxDecoration? metalDecoration;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Optional complete Metal layout, for callers with an existing surface.
  final Widget? metalChild;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    if (!glass && metalChild != null) return metalChild!;

    final radius = borderRadius ??
        metalDecoration?.borderRadius?.resolve(Directionality.of(context)) ??
        BorderRadius.circular(16);
    Widget body = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    if (onTap != null || onLongPress != null) {
      body = Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          onLongPress: onLongPress,
          child: body,
        ),
      );
    }

    if (!glass) {
      return Container(
        margin: margin,
        decoration: metalDecoration ??
            BoxDecoration(
              borderRadius: radius,
              color: color ?? Theme.of(context).colorScheme.surfaceContainer,
            ),
        child: body,
      );
    }

    final theme = AppGlassTheme.of(context);
    if (kind == AppSurfaceKind.controlGroup) {
      // No backdrop sampling or clipping: controls own their lens/glow.
      final surface = theme.scheme.surfaceContainerHigh;
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: color == null
              ? surface.withValues(alpha: 0.78)
              : Color.alphaBlend(color!.withValues(alpha: 0.30), surface),
          borderRadius: radius,
          border: Border.all(
              color: theme.scheme.outlineVariant.withValues(alpha: 0.48),),
        ),
        child: body,
      );
    }

    final overlay = kind == AppSurfaceKind.overlay;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: GlassContainer.card(
        shape: LiquidRoundedSuperellipse(borderRadius: radius.topLeft.x),
        padding: EdgeInsets.zero,
        settings: overlay ? theme.overlay : theme.control(tint: color),
        useOwnLayer: overlay,
        quality: overlay
            ? AppGlassTheme.controlQuality
            : AppGlassTheme.scrollQuality,
        child: body,
      ),
    );
  }
}
