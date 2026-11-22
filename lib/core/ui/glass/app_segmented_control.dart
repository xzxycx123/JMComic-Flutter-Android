import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../icons/app_icons.dart';
import '../../theme/app_glass_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/interface_style_scope.dart';

class AppSegment<T> {
  const AppSegment({
    required this.value,
    required this.label,
    this.icon,
    this.semanticLabel,
    this.enabled = true,
  });

  final T value;
  final Widget label;
  final Widget? icon;
  final String? semanticLabel;
  final bool enabled;
}

class AppSegmentedControl<T> extends StatelessWidget {
  const AppSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.scrollable = false,
    this.metalStyle,
    this.showSelectedIcon = false,
    this.interactiveLens = false,
  }) : assert(segments.length > 0);

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool scrollable;
  final ButtonStyle? metalStyle;
  final bool showSelectedIcon;

  /// 选中透镜按 Dock（`GlassTabBar`）标准抬升：premium 档折射/色散 + 果冻外扩。
  ///
  /// 包内 `AnimatedGlassIndicator` 的 premium 路径在 `activeIntensity > 0`
  /// （按下 / 拖动 / 回弹途中）才挂 `LiquidGlass.withOwnLayer`，静止时完全
  /// 不挂层，所以这里不需要（也不能再加）一个常驻的 own layer。只给下载页
  /// 筛选条与材质切换这两个需要与 Dock 一致的控件开启，其余分段控件保持
  /// [AppGlassTheme.controlQuality] 的轻档。
  final bool interactiveLens;

  @override
  Widget build(BuildContext context) {
    final selectedIndex =
        segments.indexWhere((segment) => segment.value == selected);
    assert(selectedIndex >= 0, 'selected must match a segment value');
    if (!context.isLiquidGlass) {
      return SegmentedButton<T>(
        segments: [
          for (final segment in segments)
            ButtonSegment<T>(
              value: segment.value,
              label:
                  Semantics(label: segment.semanticLabel, child: segment.label),
              icon: segment.icon,
              enabled: segment.enabled,
            ),
        ],
        selected: {selected},
        onSelectionChanged: (values) => onChanged(values.first),
        showSelectedIcon: showSelectedIcon,
        selectedIcon: const SvgIcon(AppIcons.check, size: 18),
        style: metalStyle,
      );
    }

    final theme = AppGlassTheme.of(context);
    const labelStyle = AppTypography.caption;
    final items = [
      for (final segment in segments)
        GlassSegment(
          id: segment.value,
          label: _plainText(segment.label),
          icon: segment.icon ??
              (_plainText(segment.label) == null ? segment.label : null),
          semanticLabel: segment.semanticLabel,
          enabled: segment.enabled,
        ),
    ];
    int? reportedIndex;
    void choose(int index) {
      final segment = segments[index];
      // Fixed glass segments report both tap-down and tap before the parent
      // has time to rebuild. Deliver a single change for that pointer gesture.
      if (!segment.enabled ||
          segment.value == selected ||
          reportedIndex == index) {
        return;
      }
      reportedIndex = index;
      onChanged(segment.value);
    }

    return Listener(
      onPointerDown: (_) => reportedIndex = null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useScrollable = scrollable ||
              segments.length < 2 ||
              segments.length > 6 ||
              _needsScroll(context, constraints.maxWidth, labelStyle);
          final height =
              (MediaQuery.textScalerOf(context).scale(labelStyle.fontSize!) +
                      26)
                  .clamp(44.0, 64.0);
          final indicator = theme.control(tint: theme.scheme.primary);
          // Dock 对齐：显式使用 Dock 解析出的 ios27 指示器透镜（thickness
          // 28 / refractiveIndex 1.17 / paraxial / rimShade 1 / rimLight 1）
          // 并把 chromaticAberration 提到 .22；静止时它没有色散，传 null
          // 只能拿到折射和果冻。control() 的平铺玻璃（CA .10、半实色底）
          // 会盖住透镜，拖动时只剩一块浅色方块。
          final indicatorSettings =
              interactiveLens ? AppGlassTheme.dockIndicatorLens : indicator;
          final indicatorQuality = interactiveLens
              ? AppGlassTheme.dockIndicatorQuality
              : AppGlassTheme.controlQuality;
          // Reduce Motion 只关运动（pinch 收缩、glow、jelly 回弹），透镜的
          // 折射与色散属于光学效果：交给 LiquidGlassWidgets.wrap 的
          // respectSystemAccessibility 在 Reduce Transparency 下整体降级，
          // 不在这里擅自把 chromaticAberration 归零。
          final pinchStrength = theme.reduceMotion
              ? 0.0
              : (interactiveLens ? AppGlassTheme.dockIndicatorPinch : .25);
          final expansion = interactiveLens
              ? AppGlassTheme.dockIndicatorExpansion
              : const EdgeInsets.symmetric(horizontal: 5, vertical: 4);
          if (useScrollable) {
            return GlassSegmentedControl.scrollable(
              segments: items,
              selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
              onSegmentSelected: choose,
              height: height,
              iconSize: 16,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              dragBehavior: SegmentDragBehavior.scroll,
              selectedTextStyle: labelStyle.copyWith(
                color: theme.accent,
                fontWeight: FontWeight.w600,
              ),
              unselectedTextStyle:
                  labelStyle.copyWith(color: theme.scheme.onSurfaceVariant),
              indicatorColor: theme.selection,
              indicatorSettings: indicatorSettings,
              indicatorPinchStrength: pinchStrength,
              indicatorExpansion: expansion,
              quality: indicatorQuality,
            );
          }
          return GlassSegmentedControl(
            segments: items,
            selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
            onSegmentSelected: choose,
            height: height,
            iconSize: 16,
            dragBehavior: theme.reduceMotion
                ? SegmentDragBehavior.scroll
                : SegmentDragBehavior.selectIndicator,
            selectedTextStyle: labelStyle.copyWith(
              color: theme.accent,
              fontWeight: FontWeight.w600,
            ),
            unselectedTextStyle:
                labelStyle.copyWith(color: theme.scheme.onSurfaceVariant),
            indicatorColor: theme.selection,
            indicatorSettings: indicatorSettings,
            indicatorPinchStrength: pinchStrength,
            indicatorExpansion: expansion,
            glowColor: theme.scheme.primary,
            glowRadius: theme.reduceMotion
                ? 0
                : (interactiveLens ? AppGlassTheme.dockIndicatorGlowRadius : 1),
            quality: indicatorQuality,
            interactionBehavior: theme.reduceMotion
                ? GlassInteractionBehavior.none
                : GlassInteractionBehavior.full,
          );
        },
      ),
    );
  }

  String? _plainText(Widget label) =>
      label is Text ? label.data ?? label.textSpan?.toPlainText() : null;

  bool _needsScroll(BuildContext context, double width, TextStyle style) {
    if (!width.isFinite) return true;
    final cellWidth = (width - 4) / segments.length;
    for (final segment in segments) {
      final painter = TextPainter(
        text: TextSpan(
          text: _plainText(segment.label) ?? '',
          style: style.copyWith(fontWeight: FontWeight.w600),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final fits = painter.width + 20 <= cellWidth;
      painter.dispose();
      if (!fits) return true;
    }
    return false;
  }
}
