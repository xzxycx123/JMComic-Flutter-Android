import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

abstract final class AppSheet {
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = false,
    bool? showDragHandle,
    bool useRootNavigator = false,
    bool useSafeArea = false,
    bool isDismissible = true,
    Color? backgroundColor,
    bool keyboardInsetHandledByBuilder = false,
  }) {
    if (!context.isLiquidGlass) {
      return showModalBottomSheet<T>(
        context: context,
        builder: builder,
        isScrollControlled: isScrollControlled,
        showDragHandle: showDragHandle,
        useRootNavigator: useRootNavigator,
        useSafeArea: useSafeArea,
        isDismissible: isDismissible,
        backgroundColor: backgroundColor,
      );
    }

    final materialTheme = Theme.of(context);
    final tokens = AppGlassTheme.of(context);
    final settings = backgroundColor == null
        ? tokens.overlay
        : tokens.overlay.copyWith(
            glassColor: backgroundColor.withValues(alpha: .86),
            bodyMode: GlassBodyMode.clear,
          );
    final startsExpanded = isScrollControlled;
    return GlassModalSheet.show<T>(
      context: context,
      useRootNavigator: useRootNavigator,
      isDismissible: isDismissible,
      dismissible: isDismissible,
      settings: settings,
      expandedColor: backgroundColor,
      expandedDarkColor: backgroundColor,
      quality: AppGlassTheme.controlQuality,
      showDragIndicator: showDragHandle ?? true,
      initialState:
          startsExpanded ? GlassSheetState.full : GlassSheetState.half,
      halfSize: .53,
      fullSize: .92,
      fillThreshold: 1,
      padding: EdgeInsets.zero,
      stretch: tokens.reduceMotion ? 0 : .22,
      sheetAnimationStyle:
          tokens.reduceMotion ? AnimationStyle.noAnimation : null,
      builder: (context) => Theme(
        data: materialTheme,
        child: Material(
          type: MaterialType.transparency,
          child: Builder(
            builder: (context) {
              final child = builder(context);
              final double keyboard = keyboardInsetHandledByBuilder
                  ? 0
                  : MediaQuery.viewInsetsOf(context).bottom;
              return SafeArea(
                top: useSafeArea,
                child: Padding(
                  padding: EdgeInsets.only(bottom: keyboard),
                  child: isScrollControlled && !keyboardInsetHandledByBuilder
                      ? child
                      : SingleChildScrollView(child: child),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
