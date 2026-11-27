import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/interface_style_scope.dart';

class AppDialogAction<T> {
  const AppDialogAction({
    required this.label,
    this.result,
    this.resultBuilder,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final T? result;
  final T? Function()? resultBuilder;
  final bool primary;
  final bool destructive;

  T? _resolve() => resultBuilder == null ? result : resultBuilder!();
}

abstract final class AppDialog {
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? message,
    WidgetBuilder? contentBuilder,
    WidgetBuilder? iconBuilder,
    required List<AppDialogAction<T>> actions,
    bool barrierDismissible = true,
  }) {
    assert(actions.isNotEmpty && actions.length <= 3);
    if (!context.isLiquidGlass) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (context) => AlertDialog(
          icon: iconBuilder?.call(context),
          title: Text(title),
          content: contentBuilder?.call(context) ??
              (message == null ? null : Text(message)),
          actions: [
            for (final action in actions) _metalAction(context, action),
          ],
        ),
      );
    }

    final materialTheme = Theme.of(context);
    BuildContext? dialogContext;
    bool closing = false;
    // 弹窗使用原生预设，保留面板的玻璃透明度。
    return GlassDialog.show<T>(
      context: context,
      title: title,
      message: message,
      quality: AppGlassTheme.overlayQuality,
      barrierDismissible: barrierDismissible,
      content: Builder(
        builder: (context) {
          dialogContext = context;
          if (contentBuilder == null && iconBuilder == null) {
            return const SizedBox.shrink();
          }
          return Theme(
            data: materialTheme,
            child: InheritedGlassSurfaceStyle(
              surfaceStyle: GlassSurfaceStyle.solid,
              child: Material(
                type: MaterialType.transparency,
                child: Builder(
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (iconBuilder != null)
                        Center(child: iconBuilder(context)),
                      if (contentBuilder != null) contentBuilder(context),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
      actions: [
        for (final action in actions)
          GlassDialogAction(
            label: action.label,
            isPrimary: action.primary,
            isDestructive: action.destructive,
            onPressed: () {
              final dialog = dialogContext;
              if (closing ||
                  dialog == null ||
                  !dialog.mounted ||
                  ModalRoute.of(dialog)?.isCurrent != true) {
                return;
              }
              closing = true;
              Navigator.of(dialog).pop<T>(action._resolve());
            },
          ),
      ],
    );
  }

  static Widget _metalAction<T>(
    BuildContext context,
    AppDialogAction<T> action,
  ) {
    final scheme = Theme.of(context).colorScheme;
    void close() {
      if (ModalRoute.of(context)?.isCurrent == true) {
        Navigator.of(context).pop<T>(action._resolve());
      }
    }

    return action.primary || action.destructive
        ? FilledButton(
            onPressed: close,
            style: action.destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            child: Text(action.label),
          )
        : TextButton(onPressed: close, child: Text(action.label));
  }
}
