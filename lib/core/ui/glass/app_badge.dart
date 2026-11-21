import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';
import 'app_chip.dart';

/// Inline status pills and optional counters anchored to an existing child.
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required Widget this.label,
    this.color,
    this.metalChild,
    this.semanticLabel,
  })  : count = null,
        anchor = null;

  const AppBadge.count({
    super.key,
    required int this.count,
    required Widget this.anchor,
    this.color,
    this.metalChild,
    this.semanticLabel,
  }) : label = null;

  final Widget? label;
  final Widget? anchor;
  final int? count;
  final Color? color;
  final Widget? metalChild;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    if (!glass && metalChild != null) return metalChild!;
    final n = count;
    if (n == null) {
      return AppChip(
        label: label!,
        color: color,
        semanticLabel: semanticLabel,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      );
    }
    if (!glass) {
      return Badge.count(count: n, backgroundColor: color, child: anchor);
    }
    final theme = AppGlassTheme.of(context);
    return GlassBadge(
      count: n,
      semanticLabel: semanticLabel,
      backgroundColor: color ?? theme.scheme.primary,
      textColor: theme.scheme.onPrimary,
      quality: AppGlassTheme.scrollQuality,
      child: anchor!,
    );
  }
}
