import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/settings_store.dart';
import '../icons/app_icons.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Metal / LiquidGlass 材质选择器，在「我的」与完整设置页共用。
class InterfaceStyleSelector extends ConsumerWidget {
  const InterfaceStyleSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(interfaceStyleProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                      '界面材质',
                      style: AppTypography.body.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (current == AppInterfaceStyle.liquidGlass)
                    Text(
                      'iOS 27',
                      style: AppTypography.caption.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<AppInterfaceStyle>(
                  segments: const <ButtonSegment<AppInterfaceStyle>>[
                    ButtonSegment<AppInterfaceStyle>(
                      value: AppInterfaceStyle.metal,
                      label: Text('Metal'),
                    ),
                    ButtonSegment<AppInterfaceStyle>(
                      value: AppInterfaceStyle.liquidGlass,
                      label: Text('LiquidGlass'),
                    ),
                  ],
                  selected: <AppInterfaceStyle>{current},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) {
                    ref
                        .read(settingsProvider.notifier)
                        .setInterfaceStyle(selection.first);
                  },
                  style: SegmentedButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                    selectedForegroundColor: scheme.primary,
                    selectedBackgroundColor: scheme.primary.withValues(
                      alpha: 0.12,
                    ),
                    side: BorderSide(color: scheme.outlineVariant),
                    textStyle: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    minimumSize: const Size(0, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Text(
                  current.description,
                  key: ValueKey<AppInterfaceStyle>(current),
                  style: AppTypography.micro.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
