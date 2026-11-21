import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/settings_store.dart';
import '../icons/app_icons.dart';
import '../ui/glass/app_badge.dart';
import '../ui/glass/app_segmented_control.dart';
import '../ui/glass/app_surface.dart';
import 'app_colors.dart';
import 'app_typography.dart';

/// Metal / LiquidGlass 材质选择器，在「我的」与完整设置页共用。
class InterfaceStyleSelector extends ConsumerWidget {
  const InterfaceStyleSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final current = ref.watch(interfaceStyleProvider);
    return AppSurface(
      kind: AppSurfaceKind.controlGroup,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(AppColors.radiusCard),
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
                  style: AppTypography.body.copyWith(color: scheme.onSurface),
                ),
              ),
              if (current == AppInterfaceStyle.liquidGlass)
                AppBadge(color: scheme.primary, label: const Text('iOS 27')),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: AppSegmentedControl<AppInterfaceStyle>(
              segments: const [
                AppSegment(
                  value: AppInterfaceStyle.metal,
                  label: Text('Metal'),
                ),
                AppSegment(
                  value: AppInterfaceStyle.liquidGlass,
                  label: Text('LiquidGlass'),
                ),
              ],
              selected: current,
              onChanged: ref.read(settingsProvider.notifier).setInterfaceStyle,
              metalStyle: SegmentedButton.styleFrom(
                foregroundColor: scheme.onSurfaceVariant,
                selectedForegroundColor: scheme.primary,
                selectedBackgroundColor: scheme.primary.withValues(alpha: 0.12),
                side: BorderSide(color: scheme.outlineVariant),
                textStyle:
                    AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                minimumSize: const Size(0, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: Text(
              current.description,
              key: ValueKey<AppInterfaceStyle>(current),
              style:
                  AppTypography.micro.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
