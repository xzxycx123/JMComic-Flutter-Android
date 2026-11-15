import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// shimmer 骨架块（不引图片素材，纯代码绘制）。
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    this.width,
    this.height,
    this.radius = AppColors.radiusCard,
  });

  final double? width;
  final double? height;
  final double radius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final shift = _controller.value * 2 - 1;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment(-1 + shift, -0.4),
              end: Alignment(1 + shift, 0.4),
              colors: <Color>[
                scheme.surfaceContainerHigh,
                scheme.surfaceContainer,
                scheme.surfaceContainerHigh,
              ],
              stops: const <double>[0.2, 0.5, 0.8],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// 首页首屏骨架：轮播 1 + 横滑 1 + 网格 6（PLAN §7.0）。
class FeedSkeleton extends StatelessWidget {
  const FeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      physics: const NeverScrollableScrollPhysics(),
      children: const <Widget>[
        ShimmerBox(height: 180, radius: AppColors.radiusCover),
        SizedBox(height: 20),
        Row(
          children: <Widget>[
            ShimmerBox(width: 140, height: 30, radius: AppColors.radiusPill),
            SizedBox(width: 10),
            ShimmerBox(width: 90, height: 30, radius: AppColors.radiusPill),
            SizedBox(width: 10),
            ShimmerBox(width: 110, height: 30, radius: AppColors.radiusPill),
          ],
        ),
        SizedBox(height: 22),
        ShimmerBox(width: 120, height: 18),
        SizedBox(height: 12),
        Row(
          children: <Widget>[
            ShimmerBox(width: 148, height: 196),
            SizedBox(width: 12),
            ShimmerBox(width: 148, height: 196),
            SizedBox(width: 12),
            ShimmerBox(width: 148, height: 196),
          ],
        ),
        SizedBox(height: 26),
        ShimmerBox(width: 120, height: 18),
        SizedBox(height: 12),
        Row(
          children: <Widget>[
            ShimmerBox(width: 170, height: 240),
            SizedBox(width: 12),
            ShimmerBox(width: 170, height: 240),
          ],
        ),
      ],
    );
  }
}

/// 通用空 / 错态块（插画或位图 + 文案 + 主按钮）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    super.key,
    this.illustration,
    this.imageAsset,
    this.imageHeight = 92,
    this.description,
    this.actionLabel,
    this.onAction,
  }) : assert(
          illustration != null || imageAsset != null,
          'EmptyState 需要 illustration 或 imageAsset',
        );

  /// SVG 插画（assets/illustrations/*.svg）。
  final String? illustration;

  /// 位图素材（assets/images/*.png，例如下载空态的火箭）。
  final String? imageAsset;
  final double imageHeight;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = imageAsset;
    // 小屏 / 键盘弹起时可用高度可能不足 280dp：缩图、隐描述，并允许整体滚动，
    // 避免「下载页输入卡 + 分段条 + 空态」在 320x480 @1.3 字体下 RenderFlex 溢出。
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        final compact = available.isFinite && available < 280;
        final effectiveImageHeight = compact ? 56.0 : imageHeight;
        final minHeight = available.isFinite && available > 32 ? available - 32 : 0.0;

        final content = Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (image != null)
              Image.asset(
                image,
                height: effectiveImageHeight,
                fit: BoxFit.contain,
                semanticLabel: title,
                errorBuilder: (context, error, stackTrace) => SizedBox(
                  height: effectiveImageHeight,
                  child: illustration == null
                      ? const SizedBox.shrink()
                      : Opacity(
                          opacity: 0.92,
                          child: SvgIllustration(illustration!),
                        ),
                ),
              )
            else
              SizedBox(
                width: compact ? 96 : 160,
                height: compact ? 72 : 120,
                child: Opacity(
                  opacity: 0.92,
                  child: SvgIllustration(illustration!),
                ),
              ),
            SizedBox(height: compact ? 10 : 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle.copyWith(color: scheme.onSurface),
            ),
            if (description != null && !compact) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              SizedBox(height: compact ? 10 : 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}
