import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/settings_store.dart';
import '../icons/app_icons.dart';
import '../ui/glass/app_chip.dart';
import '../ui/glass/app_surface.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// 明暗模式的「气泡」选择器（我的 / 设置页共用）。
///
/// 不用抽屉式底部面板：一排连续曲率的气泡，点一下即时生效。
/// LiquidGlass 皮肤走气泡的抬起/按压动效，Metal 皮肤是同一套圆角 + 填色，
/// 两套主题都能直接用（[AppChip] 的 `cornerRadius` 分支不依赖玻璃层）。
class ThemeModeSelector extends ConsumerWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(settingsProvider).themeMode;
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(AppColors.radiusCard),
      metalDecoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              IconTheme(
                data: IconThemeData(color: scheme.onSurfaceVariant),
                child: const SvgIcon(AppIcons.theme, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '主题模式',
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
              ),
              AppChip(
                kind: AppChipKind.staticLabel,
                label: Text(current.label),
                cornerRadius: AppColors.radiusPill,
                color: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                semanticLabel: '当前主题 ${current.label}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final mode in AppThemeMode.values)
                AppChip(
                  kind: AppChipKind.choice,
                  label: Text(mode.label),
                  cornerRadius: AppColors.radiusPill,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  selected: mode == current,
                  leading: mode == current
                      ? IconTheme(
                          data: IconThemeData(color: scheme.primary),
                          child: const SvgIcon(AppIcons.check, size: 14),
                        )
                      : null,
                  semanticLabel: '主题 ${mode.label}',
                  onTap: () =>
                      ref.read(settingsProvider.notifier).setThemeMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '点气泡直接切换，立即生效',
            style: AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
