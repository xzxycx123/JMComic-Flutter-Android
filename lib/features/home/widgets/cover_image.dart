import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';

/// 封面：URL 按 PLAN §5.6 自拼（列表接口的 `image` 恒为空），带 UA/Referer 头。
class CoverImage extends ConsumerWidget {
  const CoverImage({
    required this.albumId,
    super.key,
    this.radius = AppColors.radiusCard,
    this.fit = BoxFit.cover,
    this.showPlaceholderIcon = true,
  });

  final String albumId;
  final double radius;
  final BoxFit fit;
  final bool showPlaceholderIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final ready = ref.watch(jmBootstrapProvider).hasValue;
    final api = ref.watch(jmApiProvider);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: scheme.surfaceContainerHigh,
        child: !ready
            ? const _CoverPlaceholder()
            : Image(
                image: NetworkImage(
                  api.coverUrl(albumId),
                  headers: api.imageHeaders,
                ),
                fit: fit,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) return child;
                  return const _CoverPlaceholder();
                },
                errorBuilder: (context, error, stackTrace) => Center(
                  child: IconTheme(
                    data: IconThemeData(color: scheme.onSurfaceVariant),
                    child: SvgIcon(
                      AppIcons.alert,
                      size: showPlaceholderIcon ? 20 : 0,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.surfaceContainerHigh,
            scheme.surfaceContainer,
          ],
        ),
      ),
    );
  }
}
