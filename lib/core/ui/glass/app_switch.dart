import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.trackColor,
    this.trackOutlineColor,
    this.trackOutlineWidth,
    this.thumbIcon,
    this.materialTapTargetSize,
    this.dragStartBehavior = DragStartBehavior.start,
    this.mouseCursor,
    this.focusColor,
    this.hoverColor,
    this.overlayColor,
    this.splashRadius,
    this.focusNode,
    this.onFocusChange,
    this.autofocus = false,
    this.padding,
    this.semanticLabel,
  })  : _adaptive = false,
        applyCupertinoTheme = null;

  const AppSwitch.adaptive({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbColor,
    this.trackColor,
    this.trackOutlineColor,
    this.trackOutlineWidth,
    this.thumbIcon,
    this.materialTapTargetSize,
    this.dragStartBehavior = DragStartBehavior.start,
    this.mouseCursor,
    this.focusColor,
    this.hoverColor,
    this.overlayColor,
    this.splashRadius,
    this.focusNode,
    this.onFocusChange,
    this.autofocus = false,
    this.padding,
    this.semanticLabel,
    this.applyCupertinoTheme,
  }) : _adaptive = true;

  final bool _adaptive, value, autofocus;
  final bool? applyCupertinoTheme;
  final ValueChanged<bool>? onChanged, onFocusChange;
  final Color? activeColor,
      activeThumbColor,
      activeTrackColor,
      inactiveThumbColor,
      inactiveTrackColor,
      focusColor,
      hoverColor;
  final WidgetStateProperty<Color?>? thumbColor,
      trackColor,
      trackOutlineColor,
      overlayColor;
  final WidgetStateProperty<double?>? trackOutlineWidth;
  final WidgetStateProperty<Icon?>? thumbIcon;
  final MaterialTapTargetSize? materialTapTargetSize;
  final DragStartBehavior dragStartBehavior;
  final MouseCursor? mouseCursor;
  final double? splashRadius;
  final FocusNode? focusNode;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    final theme = AppGlassTheme.of(context);
    // Preserve Material-only per-state icons and outline styles if requested.
    if (!glass ||
        thumbIcon != null ||
        trackOutlineColor != null ||
        trackOutlineWidth != null) {
      final make = _adaptive ? Switch.adaptive : Switch.new;
      final control = make(
        value: value,
        onChanged: onChanged,
        activeThumbColor: activeThumbColor ?? activeColor,
        activeTrackColor: activeTrackColor ??
            (_adaptive &&
                    (Theme.of(context).platform == TargetPlatform.iOS ||
                        Theme.of(context).platform == TargetPlatform.macOS)
                ? activeColor
                : null),
        inactiveThumbColor: inactiveThumbColor,
        inactiveTrackColor: inactiveTrackColor,
        thumbColor: thumbColor,
        trackColor: trackColor,
        trackOutlineColor: trackOutlineColor,
        trackOutlineWidth: trackOutlineWidth,
        thumbIcon: thumbIcon,
        materialTapTargetSize: materialTapTargetSize,
        dragStartBehavior: dragStartBehavior,
        mouseCursor: mouseCursor,
        focusColor: focusColor,
        hoverColor: hoverColor,
        overlayColor: overlayColor,
        splashRadius: splashRadius,
        focusNode: focusNode,
        onFocusChange: onFocusChange,
        autofocus: autofocus,
        padding: padding,
      );
      // The constructor tear-off's common signature excludes applyCupertinoTheme.
      final result = _adaptive && applyCupertinoTheme != null
          ? Switch.adaptive(
              value: value,
              onChanged: onChanged,
              applyCupertinoTheme: applyCupertinoTheme,
              activeThumbColor: control.activeThumbColor,
              activeTrackColor: control.activeTrackColor,
              inactiveThumbColor: inactiveThumbColor,
              inactiveTrackColor: inactiveTrackColor,
              thumbColor: thumbColor,
              trackColor: trackColor,
              trackOutlineColor: trackOutlineColor,
              trackOutlineWidth: trackOutlineWidth,
              thumbIcon: thumbIcon,
              materialTapTargetSize: materialTapTargetSize,
              dragStartBehavior: dragStartBehavior,
              mouseCursor: mouseCursor,
              focusColor: focusColor,
              hoverColor: hoverColor,
              overlayColor: overlayColor,
              splashRadius: splashRadius,
              focusNode: focusNode,
              onFocusChange: onFocusChange,
              autofocus: autofocus,
              padding: padding,
            )
          : control;
      return semanticLabel == null
          ? result
          : Semantics(label: semanticLabel, child: result);
    }

    final states = <WidgetState>{if (onChanged == null) WidgetState.disabled};
    final activeStates = {...states, WidgetState.selected};
    final trackOn = trackColor?.resolve(activeStates) ??
        activeTrackColor ??
        theme.scheme.primary;
    final trackOff = trackColor?.resolve(states) ??
        inactiveTrackColor ??
        theme.scheme.onSurface.withValues(alpha: .18);
    final thumb = thumbColor?.resolve(value ? activeStates : states) ??
        (value ? activeThumbColor ?? activeColor : inactiveThumbColor) ??
        theme.scheme.onPrimary;
    Widget control = GlassSwitch(
      value: value,
      onChanged: onChanged,
      width: 56,
      height: 28,
      activeColor: trackOn,
      inactiveColor: trackOff,
      thumbColor: thumb,
      settings: theme.control(
          tint: value ? trackOn : null, enabled: onChanged != null,),
      quality: AppGlassTheme.controlQuality,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
    );
    if (onFocusChange != null) {
      control = Focus(
          canRequestFocus: false, onFocusChange: onFocusChange, child: control,);
    }
    return Padding(padding: padding ?? EdgeInsets.zero, child: control);
  }
}
