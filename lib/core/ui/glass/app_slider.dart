import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.focusNode,
    this.autofocus = false,
    this.padding,
    this.confineGlassThumb = false,
    this.onGlassDragCancel,
  })  : assert(value >= min && value <= max),
        assert(divisions == null || divisions > 0);

  final double value, min, max;
  final ValueChanged<double>? onChanged, onChangeStart, onChangeEnd;
  final int? divisions;
  final String? label;
  final Color? activeColor, inactiveColor, thumbColor;
  final FocusNode? focusNode;
  final bool autofocus;
  final EdgeInsetsGeometry? padding;

  /// Leaves room for the lifted lens at the ends, without painting over labels.
  final bool confineGlassThumb;
  final VoidCallback? onGlassDragCancel;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  double? _dragValue;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final slider = widget;
    if (!context.isLiquidGlass) {
      return Slider(
        value: slider.value,
        onChanged: slider.onChanged,
        onChangeStart: slider.onChangeStart,
        onChangeEnd: slider.onChangeEnd,
        min: slider.min,
        max: slider.max,
        divisions: slider.divisions,
        label: slider.label,
        activeColor: slider.activeColor,
        inactiveColor: slider.inactiveColor,
        thumbColor: slider.thumbColor,
        focusNode: slider.focusNode,
        autofocus: slider.autofocus,
        padding: slider.padding,
      );
    }
    final theme = AppGlassTheme.of(context);
    final hasRange = slider.max > slider.min;
    final enabled = slider.onChanged != null && hasRange;
    final current = hasRange ? slider.value : 0.0;
    final thumbRadius = slider.confineGlassThumb ? 12.0 : 15.0;
    void commitStep(double value) {
      slider.onChangeStart?.call(slider.value);
      slider.onChanged!(value);
      slider.onChangeEnd?.call(value);
    }

    Widget track = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: slider.confineGlassThumb ? 14 : 0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width =
              constraints.hasBoundedWidth ? constraints.maxWidth : 144.0;
          return SizedBox(
            width: width,
            child: Listener(
              onPointerCancel: (_) {
                final wasDragging = _dragging;
                _dragging = false;
                _dragValue = null;
                if (wasDragging) slider.onGlassDragCancel?.call();
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                excludeFromSemantics: true,
                onTapUp: enabled && width > thumbRadius * 2
                    ? (details) {
                        // The package recognises horizontal drags only. Flutter's
                        // gesture arena prevents this tap from firing on those drags.
                        final fraction =
                            ((details.localPosition.dx - thumbRadius) /
                                    (width - thumbRadius * 2))
                                .clamp(0.0, 1.0);
                        var logical =
                            Directionality.of(context) == TextDirection.rtl
                                ? 1 - fraction
                                : fraction;
                        final divisions = slider.divisions;
                        if (divisions != null) {
                          logical = (logical * divisions).round() / divisions;
                        }
                        commitStep(
                          slider.min + logical * (slider.max - slider.min),
                        );
                      }
                    : null,
                child: GlassSlider(
                  thumbRadius: thumbRadius,
                  value: current,
                  onChanged: enabled
                      ? (value) {
                          if (_dragging) {
                            _dragValue = value;
                            slider.onChanged!(value);
                          } else {
                            // The plugin calls only onChanged for assistive actions; commit
                            // the single-step interaction just like a slider release.
                            commitStep(value);
                          }
                        }
                      : null,
                  onChangeStart: enabled
                      ? (value) {
                          _dragging = true;
                          _dragValue = value;
                          slider.onChangeStart?.call(value);
                        }
                      : null,
                  onChangeEnd: enabled
                      ? (value) {
                          // v1.19 calls onChangeEnd with widget.value, which may predate the
                          // last drag event if Flutter has not rebuilt yet.
                          final target = _dragValue ?? value;
                          _dragging = false;
                          _dragValue = null;
                          slider.onChangeEnd?.call(target);
                        }
                      : null,
                  min: hasRange ? slider.min : 0,
                  max: hasRange ? slider.max : 1,
                  divisions: slider.divisions,
                  label: slider.label,
                  activeColor: slider.activeColor ?? theme.scheme.primary,
                  inactiveColor: slider.inactiveColor ??
                      theme.scheme.onSurface.withValues(alpha: .22),
                  thumbColor: slider.thumbColor ?? theme.scheme.onPrimary,
                  focusNode: slider.focusNode,
                  autofocus: slider.autofocus,
                  settings:
                      theme.control(tint: slider.activeColor, enabled: enabled),
                  quality: AppGlassTheme.controlQuality,
                  interactionBehavior: theme.reduceMotion
                      ? GlassInteractionBehavior.none
                      : GlassInteractionBehavior.full,
                ),
              ),
            ),
          );
        },
      ),
    );
    if (slider.confineGlassThumb) track = ClipRect(child: track);
    return Padding(padding: slider.padding ?? EdgeInsets.zero, child: track);
  }
}
