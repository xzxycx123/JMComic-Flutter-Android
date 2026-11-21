import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'app_colors.dart';

/// App-specific tints and performance budgets layered on the iOS 27 preset.
class AppGlassTheme {
  const AppGlassTheme._(this.scheme, this.reduceMotion);

  static const preset = GlassThemeData.ios27();
  static const scrollQuality = GlassQuality.standard;
  static const controlQuality = GlassQuality.standard;
  static const overlayQuality = GlassQuality.premium;

  factory AppGlassTheme.of(BuildContext context, {bool reader = false}) =>
      AppGlassTheme._(
        reader ? AppColors.darkScheme : Theme.of(context).colorScheme,
        MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      );

  final ColorScheme scheme;
  final bool reduceMotion;

  bool get isDark => scheme.brightness == Brightness.dark;
  Color get accent => isDark ? scheme.primary : scheme.onPrimaryContainer;
  Color get selection => scheme.primary.withValues(alpha: isDark ? .24 : .18);
  Color get selectionInk => AppColors.darkOnPrimary;
  Color get outline => Color.lerp(scheme.outline, scheme.onSurface, .13)!;

  Gradient get background => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.lerp(scheme.surface, scheme.primaryContainer, .45)!,
          scheme.surface,
          Color.lerp(scheme.surface, scheme.secondary, .08)!,
        ],
        stops: const [0, .48, 1],
      );

  LiquidGlassSettings get _base =>
      (isDark ? GlassThemeSettings.ios27Dark : GlassThemeSettings.ios27Light)
          .applyTo(const LiquidGlassSettings());

  LiquidGlassSettings control({
    Color? tint,
    bool strong = false,
    bool enabled = true,
  }) {
    final base = Color.lerp(
      scheme.surfaceContainer,
      tint ?? scheme.primary,
      strong ? (isDark ? .36 : .29) : (tint != null ? .14 : 0),
    )!;
    return _base.copyWith(
      glassColor: base.withValues(alpha: strong ? .78 : (isDark ? .52 : .57)),
      bodyMode: strong ? GlassBodyMode.clear : GlassBodyMode.adaptive,
      blur: strong ? 10 : 6,
      thickness: strong ? 20 : 12,
      lightIntensity: enabled ? (strong ? .7 : .46) : .20,
      chromaticAberration: reduceMotion ? 0 : .10,
    );
  }

  LiquidGlassSettings get overlay => _base.copyWith(
        glassColor:
            scheme.surfaceContainer.withValues(alpha: isDark ? .82 : .84),
        blur: 15,
        thickness: 16,
        chromaticAberration: 0,
      );

  LiquidGlassSettings get chrome => _base.copyWith(
        glassColor: scheme.surface.withValues(alpha: isDark ? .82 : .76),
        blur: 9,
        thickness: 8,
        chromaticAberration: 0,
      );
}
