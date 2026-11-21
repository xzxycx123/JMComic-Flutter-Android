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
  }) : assert(segments.length > 0);

  final List<AppSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool scrollable;
  final ButtonStyle? metalStyle;
  final bool showSelectedIcon;

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
              indicatorSettings: indicator,
              indicatorPinchStrength: theme.reduceMotion ? 0 : .25,
              indicatorExpansion:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              quality: AppGlassTheme.controlQuality,
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
            indicatorSettings: indicator,
            indicatorPinchStrength: theme.reduceMotion ? 0 : .25,
            indicatorExpansion:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
            glowColor: theme.scheme.primary,
            glowRadius: theme.reduceMotion ? 0 : 1,
            quality: AppGlassTheme.controlQuality,
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
