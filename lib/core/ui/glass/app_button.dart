import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/interface_style_scope.dart';

enum AppButtonVariant { primary, secondary, text, destructive }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.onPressed,
    this.child,
    this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.variant = AppButtonVariant.primary,
    this.loading = false,
    this.expanded = false,
    this.semanticLabel,
    this.style,
    this.foregroundColor,
    this.height,
    this.padding,
    this.cornerRadius = 12,
    this.solid = false,
  }) : assert(label != null || child != null);

  const AppButton.text({
    Key? key,
    required VoidCallback? onPressed,
    Widget? child,
    String? label,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool loading = false,
    bool expanded = false,
    String? semanticLabel,
    ButtonStyle? style,
    Color? foregroundColor,
    double? height,
    EdgeInsetsGeometry? padding,
    double cornerRadius = 12,
    bool solid = false,
  }) : this(
          key: key,
          onPressed: onPressed,
          child: child,
          label: label,
          leadingIcon: leadingIcon,
          trailingIcon: trailingIcon,
          loading: loading,
          expanded: expanded,
          semanticLabel: semanticLabel,
          style: style,
          foregroundColor: foregroundColor,
          height: height,
          padding: padding,
          cornerRadius: cornerRadius,
          solid: solid,
          variant: AppButtonVariant.text,
        );

  const AppButton.secondary({
    Key? key,
    required VoidCallback? onPressed,
    Widget? child,
    String? label,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool loading = false,
    bool expanded = false,
    String? semanticLabel,
    ButtonStyle? style,
    Color? foregroundColor,
    double? height,
    EdgeInsetsGeometry? padding,
    double cornerRadius = 12,
    bool solid = false,
  }) : this(
          key: key,
          onPressed: onPressed,
          child: child,
          label: label,
          leadingIcon: leadingIcon,
          trailingIcon: trailingIcon,
          loading: loading,
          expanded: expanded,
          semanticLabel: semanticLabel,
          style: style,
          foregroundColor: foregroundColor,
          height: height,
          padding: padding,
          cornerRadius: cornerRadius,
          solid: solid,
          variant: AppButtonVariant.secondary,
        );

  const AppButton.destructive({
    Key? key,
    required VoidCallback? onPressed,
    Widget? child,
    String? label,
    Widget? leadingIcon,
    Widget? trailingIcon,
    bool loading = false,
    bool expanded = false,
    String? semanticLabel,
    ButtonStyle? style,
    Color? foregroundColor,
    double? height,
    EdgeInsetsGeometry? padding,
    double cornerRadius = 12,
    bool solid = false,
  }) : this(
          key: key,
          onPressed: onPressed,
          child: child,
          label: label,
          leadingIcon: leadingIcon,
          trailingIcon: trailingIcon,
          loading: loading,
          expanded: expanded,
          semanticLabel: semanticLabel,
          style: style,
          foregroundColor: foregroundColor,
          height: height,
          padding: padding,
          cornerRadius: cornerRadius,
          solid: solid,
          variant: AppButtonVariant.destructive,
        );

  final VoidCallback? onPressed;
  final Widget? child;
  final String? label;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final AppButtonVariant variant;
  final bool loading;
  final bool expanded;
  final String? semanticLabel;
  final ButtonStyle? style;
  final Color? foregroundColor;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double cornerRadius;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final glass = context.isLiquidGlass;
    final scheme = Theme.of(context).colorScheme;
    final action = loading ? null : onPressed;
    final shape = LiquidRoundedSuperellipse(borderRadius: cornerRadius);
    final text =
        child ?? Text(label!, maxLines: 1, overflow: TextOverflow.ellipsis);
    final first = loading
        ? SizedBox.square(
            dimension: 16,
            child: glass
                ? const GlassProgressIndicator.circular(
                    size: 16,
                    strokeWidth: 2,
                  )
                : const CircularProgressIndicator(strokeWidth: 2),
          )
        : leadingIcon;
    final contents = first == null && trailingIcon == null
        ? text
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (first != null) ...[first, const SizedBox(width: 8)],
              Flexible(child: text),
              if (trailingIcon != null) ...[
                const SizedBox(width: 8),
                trailingIcon!,
              ],
            ],
          );

    Widget button;
    if (!glass) {
      final color = foregroundColor ??
          (variant == AppButtonVariant.destructive ? scheme.onError : null);
      final buttonStyle = (variant == AppButtonVariant.destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: scheme.error, foregroundColor: color,)
                  : const ButtonStyle())
              .merge(style)
          .copyWith(
        shape: WidgetStatePropertyAll(shape),
        padding: padding == null ? null : WidgetStatePropertyAll(padding),
        foregroundColor: foregroundColor == null
            ? null
            : WidgetStatePropertyAll(foregroundColor),
      );
      button = switch (variant) {
        AppButtonVariant.primary ||
        AppButtonVariant.destructive =>
          FilledButton(onPressed: action, style: buttonStyle, child: contents),
        AppButtonVariant.secondary => OutlinedButton(
            onPressed: action,
            style: buttonStyle,
            child: contents,
          ),
        AppButtonVariant.text =>
          TextButton(onPressed: action, style: buttonStyle, child: contents),
      };
      if (height != null) button = SizedBox(height: height, child: button);
      if (semanticLabel != null) {
        button = Semantics(
          label: semanticLabel,
          button: true,
          enabled: action != null,
          onTap: action,
          excludeSemantics: true,
          child: button,
        );
      }
    } else {
      final tokens = AppGlassTheme.of(context);
      final destructive = variant == AppButtonVariant.destructive;
      final prominent = variant == AppButtonVariant.primary || destructive;
      final textOnly = variant == AppButtonVariant.text;
      final foreground = foregroundColor ??
          switch (variant) {
            AppButtonVariant.primary => scheme.onPrimaryContainer,
            AppButtonVariant.secondary => scheme.onSurface,
            AppButtonVariant.text => tokens.accent,
            AppButtonVariant.destructive => scheme.onSurface,
          };
      final tint = destructive ? scheme.error : scheme.primary;
      final ink = action == null ? scheme.onSurfaceVariant : foreground;
      final solidSurface = solid ||
          InheritedGlassSurfaceStyle.maybeOf(context) ==
              GlassSurfaceStyle.solid;
      button = GlassButton.custom(
        shape: shape,
        onTap: action ?? _noop,
        enabled: action != null,
        label: semanticLabel ?? '',
        settings: solidSurface
            ? null
            : tokens.control(
                tint: prominent ? tint : null,
                strong: prominent,
                enabled: action != null,
              ),
        style:
            textOnly ? GlassButtonStyle.transparent : GlassButtonStyle.filled,
        surfaceStyle:
            solidSurface ? GlassSurfaceStyle.solid : GlassSurfaceStyle.glass,
        color: solidSurface && !textOnly && prominent
            ? (destructive ? scheme.errorContainer : scheme.primaryContainer)
            : null,
        quality: solidSurface ? null : AppGlassTheme.controlQuality,
        interactionScale: tokens.reduceMotion ? 1 : .96,
        stretch: tokens.reduceMotion ? 0 : .22,
        anchorStretch: !tokens.reduceMotion,
        glowColor: prominent ? tint : null,
        pressLightColor: prominent ? tint : null,
        glowRadius: tokens.reduceMotion ? 0 : 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: height ?? (textOnly ? 44 : 48),
            minWidth: 44,
          ),
          child: Padding(
            padding: padding ??
                (textOnly
                    ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                    : const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: IconTheme.merge(
                data: IconThemeData(color: ink),
                child: DefaultTextStyle.merge(
                  style: AppTypography.bodyStrong.copyWith(
                    color: ink,
                    decoration: TextDecoration.none,
                  ),
                  child: contents,
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (loading) button = Semantics(liveRegion: true, child: button);
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  static void _noop() {}
}
