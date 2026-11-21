import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../core/icons/app_icons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_glass_theme.dart';
import '../../core/theme/app_typography.dart';

/// 默认 Metal 胶囊 Dock（两档：首页 / 我的；下载与历史收进「我的」）。
class GlassNavBar extends StatelessWidget {
  const GlassNavBar({
    required this.currentIndex,
    required this.onSelect,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  static const List<({String icon, String label})> items =
      <({String icon, String label})>[
    (icon: AppIcons.home, label: '首页'),
    (icon: AppIcons.user, label: '我的'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppColors.radiusPill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(AppColors.radiusPill),
                border: Border.all(color: scheme.outline),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  for (var index = 0; index < items.length; index++)
                    Expanded(
                      child: _NavItem(
                        icon: items[index].icon,
                        label: items[index].label,
                        selected: index == currentIndex,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelect(index);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// iOS 27 Liquid Glass Dock：悬浮玻璃底盘 + 弹性选中透镜 + 动态光影。
class LiquidGlassNavBar extends StatelessWidget {
  const LiquidGlassNavBar({
    required this.currentIndex,
    required this.onSelect,
    super.key,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = AppGlassTheme.of(context);
    final scheme = tokens.scheme;
    return GlassTabBar.bottom(
      tabs: <GlassTab>[
        for (final item in GlassNavBar.items)
          GlassTab(
            icon: SvgIcon(item.icon, size: 22),
            activeIcon: SvgIcon(item.icon, size: 22),
            label: item.label,
            semanticLabel: item.label,
          ),
      ],
      selectedIndex: currentIndex,
      onTabSelected: (index) {
        HapticFeedback.selectionClick();
        onSelect(index);
      },
      iconSize: 22,
      selectedIconColor: tokens.accent,
      unselectedIconColor: scheme.onSurfaceVariant,
      selectedLabelColor: tokens.accent,
      unselectedLabelColor: scheme.onSurfaceVariant,
      selectedLabelStyle: AppTypography.micro.copyWith(
        inherit: false,
        color: tokens.accent,
        decoration: TextDecoration.none,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: AppTypography.micro.copyWith(
        inherit: false,
        color: scheme.onSurfaceVariant,
        decoration: TextDecoration.none,
      ),
      indicatorColor: tokens.selection,
      interactionGlowColor: scheme.primary,
      interactionBehavior: tokens.reduceMotion
          ? GlassInteractionBehavior.none
          : GlassInteractionBehavior.full,
      indicatorPinchStrength: tokens.reduceMotion ? 0 : .4,
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Center(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.elasticOut,
          padding: EdgeInsets.symmetric(
            horizontal: selected ? 16 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppColors.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconTheme(
                data: IconThemeData(color: color),
                child: SvgIcon(icon, size: 22),
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTypography.caption.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
