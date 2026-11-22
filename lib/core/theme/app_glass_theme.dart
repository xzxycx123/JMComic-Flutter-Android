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

  /// Dock（`GlassTabBar`）指示器的官方标定值：抬起的指示器透镜用 premium
  /// 档才有真实折射与色散，pinch / 外扩 / glow 决定「放大 + 果冻」的手感。
  /// 只给需要与 Dock 对齐的分段控件复用，其余控件仍用 [controlQuality]。
  static const dockIndicatorQuality = GlassQuality.premium;
  static const double dockIndicatorPinch = .4;
  static const double dockIndicatorGlowRadius = 1.5;
  static const EdgeInsets dockIndicatorExpansion =
      EdgeInsets.symmetric(horizontal: 12, vertical: 8);

  /// 指示器透镜色散强度。
  ///
  /// 包内 [LiquidGlassSettings.ios27Indicator]（Dock 实际解析到的预设）是
  /// `thickness: 28, refractiveIndex: 1.17, paraxial, rimShade: 1,
  /// rimLight: 1, chromaticAberration: 0`——只有折射和果冻，没有色散；
  /// 旧实现用的 `control()` 平铺玻璃也只有 .10，肉眼几乎看不出。
  /// 取 .22：约等于 Figma dispersion 5.5%（4 × 5.5%），比经典指示器预设的
  /// .3 收敛，又明显高于 .10，拖动时能看清边缘的彩色分离。
  static const double dockIndicatorDispersion = .22;

  /// Dock 解析出的 ios27 指示器透镜 + 明确色散；其余光学参数（厚度、
  /// 折射率、paraxial 透镜、rimShade / rimLight）与 Dock 完全一致。
  static final LiquidGlassSettings dockIndicatorLens = LiquidGlassSettings
      .ios27Indicator
      .copyWith(chromaticAberration: dockIndicatorDispersion);

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
