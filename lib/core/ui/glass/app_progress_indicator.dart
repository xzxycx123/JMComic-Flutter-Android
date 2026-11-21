import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator.circular({
    super.key,
    this.value,
    this.strokeWidth,
    this.size,
    this.color,
    this.backgroundColor,
    this.semanticsLabel,
    this.semanticsValue,
  })  : _linear = false,
        minHeight = null;

  const AppProgressIndicator.linear({
    super.key,
    this.value,
    this.minHeight,
    this.color,
    this.backgroundColor,
    this.semanticsLabel,
    this.semanticsValue,
  })  : _linear = true,
        strokeWidth = null,
        size = null;

  final bool _linear;
  final double? value, minHeight, strokeWidth, size;
  final Color? color, backgroundColor;
  final String? semanticsLabel, semanticsValue;

  @override
  Widget build(BuildContext context) {
    if (!context.isLiquidGlass) {
      if (_linear) {
        return LinearProgressIndicator(
          value: value,
          minHeight: minHeight,
          color: color,
          backgroundColor: backgroundColor,
          semanticsLabel: semanticsLabel,
          semanticsValue: semanticsValue,
        );
      }
      final indicator = CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        color: color,
        backgroundColor: backgroundColor,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
      );
      return size == null
          ? indicator
          : SizedBox.square(dimension: size, child: indicator);
    }
    final theme = AppGlassTheme.of(context);
    final track =
        backgroundColor ?? theme.scheme.onSurface.withValues(alpha: .15);
    final effectiveColor = color ?? theme.scheme.primary;
    final progress = value?.clamp(0.0, 1.0);
    final indicator = _linear
        ? GlassProgressIndicator.linear(
            value: progress,
            height: minHeight ?? 4,
            minWidth: 0,
            color: effectiveColor,
            backgroundColor: track,
            quality: AppGlassTheme.scrollQuality,
            semanticLabel: semanticsLabel,
          )
        : GlassProgressIndicator.circular(
            value: progress,
            size: size ?? 20,
            strokeWidth: strokeWidth ?? 2.5,
            color: effectiveColor,
            backgroundColor: track,
            quality: AppGlassTheme.scrollQuality,
            semanticLabel: semanticsLabel,
          );
    return semanticsValue == null
        ? indicator
        : Semantics(
            label: semanticsLabel ??
                MaterialLocalizations.of(context).modalBarrierDismissLabel,
            value: semanticsValue,
            child: ExcludeSemantics(child: indicator),
          );
  }
}
