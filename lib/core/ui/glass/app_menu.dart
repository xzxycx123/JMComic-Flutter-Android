import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../theme/app_glass_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/interface_style_scope.dart';

class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final Widget? icon;
  final bool destructive;
}

/// Keeps the menu's values independent of the labels shown in either material.
class AppMenu<T> extends StatelessWidget {
  const AppMenu({
    super.key,
    required this.icon,
    required this.items,
    required this.onSelected,
    this.tooltip,
  });

  final Widget icon;
  final List<AppMenuItem<T>> items;
  final ValueChanged<T> onSelected;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (!context.isLiquidGlass) {
      return PopupMenuButton<T>(
        icon: icon,
        tooltip: tooltip,
        enabled: items.isNotEmpty,
        onSelected: onSelected,
        itemBuilder: (_) => [
          for (final item in items)
            PopupMenuItem<T>(
              value: item.value,
              child: item.icon == null
                  ? Text(item.label)
                  : Row(
                      children: [
                        item.icon!,
                        const SizedBox(width: 10),
                        Flexible(child: Text(item.label)),
                      ],
                    ),
            ),
        ],
      );
    }

    final theme = AppGlassTheme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();
    final label = tooltip ?? '操作菜单';
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: GlassPullDownButton(
        icon: icon,
        semanticLabel: label,
        menuSemanticLabel: label,
        quality: AppGlassTheme.controlQuality,
        settings: theme.overlay,
        // A task row remains scrollable; opening the menu requires a tap.
        enableContinuousSwipe: false,
        items: [
          for (final item in items)
            GlassMenuItem(
              title: item.label,
              icon: item.icon,
              isDestructive: item.destructive,
              titleStyle: AppTypography.body.copyWith(
                color: item.destructive
                    ? theme.scheme.error
                    : theme.scheme.onSurface,
              ),
              enablePressScale: !theme.reduceMotion,
              onTap: () => onSelected(item.value),
            ),
        ],
      ),
    );
  }
}
