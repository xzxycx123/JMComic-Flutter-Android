import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.style,
    this.readOnly = false,
    this.autofocus = false,
    this.obscureText = false,
    this.autocorrect,
    this.enableSuggestions = true,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.maxLengthEnforcement,
    this.onChanged,
    this.onEditingComplete,
    this.onSubmitted,
    this.inputFormatters,
    this.enabled,
    this.cursorColor,
    this.onTapOutside,
    this.onTap,
    this.autofillHints = const <String>[],
    this.selectionControls,
    this.enableInteractiveSelection,
    this.cornerRadius,
    this.contentPadding,
    this.expands = false,
    this.textAlignVertical,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final TextStyle? style;
  final bool readOnly, autofocus, obscureText, enableSuggestions;
  final bool? enabled, enableInteractiveSelection, autocorrect;
  final int? maxLines, minLines, maxLength;
  final MaxLengthEnforcement? maxLengthEnforcement;
  final ValueChanged<String>? onChanged, onSubmitted;
  final VoidCallback? onEditingComplete, onTap;
  final List<TextInputFormatter>? inputFormatters;
  final Color? cursorColor;
  final TapRegionCallback? onTapOutside;
  final Iterable<String>? autofillHints;
  final TextSelectionControls? selectionControls;

  /// 非空时两套材质（Metal / LiquidGlass）都渲染同一枚「圆角矩形 + 连续曲率」
  /// 输入框：Metal 用实色底板，LiquidGlass 用同形状的玻璃/实色井。留空保持
  /// 各材质原有外观。
  final double? cornerRadius;

  /// 圆角矩形输入框的内边距；默认左上角 14/12，文字统一从左上起始。
  final EdgeInsetsGeometry? contentPadding;

  /// 撑满父级给出的高度（配合固定 `SizedBox` 高度使用，多行输入不再按行数
  /// 撑高）。开启时 `maxLines` / `minLines` 必须为空。
  final bool expands;

  final TextAlignVertical? textAlignVertical;

  @protected
  bool get isSearch => false;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  TextEditingController? _localController;
  FocusNode? _localFocus;
  TextEditingController get _controller =>
      widget.controller ?? (_localController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_localFocus ??= FocusNode());

  @override
  void dispose() {
    _localController?.dispose();
    _localFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = widget;
    final glass = context.isLiquidGlass;
    final theme = AppGlassTheme.of(context);
    final decoration = field.decoration;
    final enabled = field.enabled ?? decoration?.enabled ?? true;
    final solid = InheritedGlassSurfaceStyle.maybeOf(context) ==
            GlassSurfaceStyle.solid ||
        field.isSearch;
    // 调用方要求「圆角矩形 + 连续曲率」时，Metal 与 LiquidGlass 共用同一形状。
    final shaped = field.cornerRadius != null;
    final shape = LiquidRoundedSuperellipse(
      borderRadius: field.cornerRadius ?? (field.isSearch ? 22 : 14),
    );
    final inset =
        field.contentPadding ?? const EdgeInsets.fromLTRB(14, 12, 14, 12);
    // The package uses CupertinoTextField. Preserve Material adornment layout,
    // counters, tap groups, cursor overrides and editing hooks when requested.
    final simple = !shaped &&
        decoration != null &&
        (decoration == InputDecoration(hintText: decoration.hintText) ||
            decoration == const InputDecoration()) &&
        field.maxLines == 1 &&
        field.maxLength == null &&
        field.maxLengthEnforcement == null &&
        field.cursorColor == null &&
        field.onEditingComplete == null &&
        field.onTap == null &&
        field.onTapOutside != null &&
        field.enableInteractiveSelection == null &&
        !field.obscureText &&
        !field.readOnly;
    if (glass && simple) {
      return GlassTextField(
        controller: _controller,
        focusNode: _focus,
        placeholder: decoration.hintText,
        textStyle: field.style ?? Theme.of(context).textTheme.bodyLarge,
        placeholderStyle: TextStyle(color: theme.scheme.onSurfaceVariant),
        keyboardType: field.keyboardType,
        textInputAction: field.textInputAction,
        textCapitalization: field.textCapitalization,
        minLines: field.minLines,
        enabled: enabled,
        autofocus: field.autofocus,
        onChanged: field.onChanged,
        onSubmitted: field.onSubmitted,
        inputFormatters: field.inputFormatters,
        autofillHints: field.autofillHints,
        autocorrect: field.autocorrect ?? true,
        enableSuggestions: field.enableSuggestions,
        selectionControls:
            field.selectionControls ?? materialTextSelectionHandleControls,
        onTapOutside: field.onTapOutside,
        shape: shape,
        surfaceStyle: solid ? GlassSurfaceStyle.solid : null,
        settings: theme.control(enabled: enabled),
        quality: AppGlassTheme.controlQuality,
        interactionBehavior: theme.reduceMotion
            ? GlassInteractionBehavior.none
            : GlassInteractionBehavior.full,
      );
    }

    Widget input = TextField(
      controller: _controller,
      focusNode: _focus,
      decoration: glass || shaped
          ? decoration?.copyWith(
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: shaped ? inset : null,
            )
          : decoration,
      keyboardType: field.keyboardType,
      textInputAction: field.textInputAction,
      textCapitalization: field.textCapitalization,
      style: field.style,
      readOnly: field.readOnly,
      autofocus: field.autofocus,
      obscureText: field.obscureText,
      autocorrect: field.autocorrect,
      enableSuggestions: field.enableSuggestions,
      maxLines: field.maxLines,
      minLines: field.minLines,
      expands: field.expands,
      textAlignVertical: field.textAlignVertical ??
          (field.expands ? TextAlignVertical.top : null),
      maxLength: field.maxLength,
      maxLengthEnforcement: field.maxLengthEnforcement,
      onChanged: field.onChanged,
      onEditingComplete: field.onEditingComplete,
      onSubmitted: field.onSubmitted,
      inputFormatters: field.inputFormatters,
      enabled: field.enabled,
      cursorColor: field.cursorColor ?? (glass ? theme.accent : null),
      onTapOutside: field.onTapOutside,
      onTap: field.onTap,
      autofillHints: field.autofillHints,
      selectionControls: field.selectionControls,
      enableInteractiveSelection: field.enableInteractiveSelection,
    );
    if (!glass && !shaped) return input;
    if (decoration != null &&
        decoration.contentPadding == null &&
        !field.isSearch &&
        !shaped) {
      input = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        child: input,
      );
    }
    return ListenableBuilder(
      listenable: _focus,
      child: input,
      builder: (context, child) {
        final focused = _focus.hasFocus && enabled;
        if (!glass) {
          // Metal：与 LiquidGlass 完全同形的「圆角矩形 + 连续曲率」实色井，
          // 文字从左上起始（内边距由 contentPadding 统一给出）。
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: theme.scheme.surfaceContainerHigh,
              shape: shape.copyWith(
                side: BorderSide(
                  color: focused
                      ? theme.scheme.primary
                      : theme.scheme.outlineVariant,
                ),
              ),
            ),
            child: child!,
          );
        }
        if (solid) {
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: theme.scheme.surfaceContainerHigh,
              shape: shape.copyWith(
                side: BorderSide(
                  color: focused ? theme.accent : theme.scheme.outlineVariant,
                ),
              ),
            ),
            child: child!,
          );
        }
        return AdaptiveGlass(
          shape: shape,
          settings: theme.control(
            tint: focused ? theme.scheme.primary : null,
            enabled: enabled,
          ),
          quality: AppGlassTheme.controlQuality,
          useOwnLayer: false,
          clipBehavior: Clip.none,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              shape: shape.copyWith(
                side: BorderSide(
                  color: focused
                      ? theme.accent
                      : theme.scheme.outlineVariant.withValues(alpha: .55),
                ),
              ),
            ),
            child: child!,
          ),
        );
      },
    );
  }
}
