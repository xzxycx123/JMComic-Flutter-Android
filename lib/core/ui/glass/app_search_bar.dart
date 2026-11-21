import 'app_text_field.dart';

/// Same editing contract as [AppTextField], with a search-shaped glass well.
class AppSearchBar extends AppTextField {
  const AppSearchBar({
    super.key,
    super.controller,
    super.focusNode,
    super.decoration,
    super.keyboardType,
    super.textInputAction,
    super.textCapitalization,
    super.style,
    super.readOnly,
    super.autofocus,
    super.obscureText,
    super.autocorrect,
    super.enableSuggestions,
    super.maxLines,
    super.minLines,
    super.maxLength,
    super.maxLengthEnforcement,
    super.onChanged,
    super.onEditingComplete,
    super.onSubmitted,
    super.inputFormatters,
    super.enabled,
    super.cursorColor,
    super.onTapOutside,
    super.onTap,
    super.autofillHints,
    super.selectionControls,
    super.enableInteractiveSelection,
  });

  @override
  bool get isSearch => true;
}
