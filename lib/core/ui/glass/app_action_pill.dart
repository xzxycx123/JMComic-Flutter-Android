import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../icons/app_icons.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_glass_theme.dart';
import '../../theme/app_typography.dart';
import '../../theme/interface_style_scope.dart';

/// 详情页的胶囊动作按钮（点赞 / 写评论）。
///
/// 两套材质共用同一枚「药丸 + 连续曲率」形状（[LiquidRoundedSuperellipse]），
/// 区别只在表面：
/// - **Metal**：实色胶囊（常态 `surfaceContainer` + 细描边、选中/主操作
///   `primaryContainer`），按下走 InkWell 水波。
/// - **LiquidGlass**：iOS 27 折射胶囊，沿用应用主按钮那套
///   [AppGlassTheme.control] optics —— 选中淡主色、主操作 `strong` 主色，
///   并带按压光、辉光与果冻拉伸。
class AppActionPill extends StatelessWidget {
  const AppActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
    this.active = false,
    this.prominent = false,
    this.semanticLabel,
  });

  /// `assets/icons/*.svg` 路径（项目唯一图标入口）。
  final String icon;
  final String label;
  final VoidCallback onTap;

  /// 选中态（例如已点赞）：胶囊换成淡主色。
  final bool active;

  /// 主操作（写评论）：LiquidGlass 下用 `strong` 主色 optics（与详情页
  /// 主按钮同一档），Metal 下用 `primaryContainer`。
  final bool prominent;

  final String? semanticLabel;

  static const double height = 36;
  static const EdgeInsets _inset = EdgeInsets.symmetric(horizontal: 14);
  static const LiquidRoundedSuperellipse _shape =
      LiquidRoundedSuperellipse(borderRadius: AppColors.radiusPill);

  @override
  Widget build(BuildContext context) {
    final tokens = AppGlassTheme.of(context);
    final scheme = tokens.scheme;
    final glass = context.isLiquidGlass;
    // 已经处在 solid 卡片/表单里的胶囊不再开折射层（避免玻璃套玻璃）。
    final solid = glass &&
        InheritedGlassSurfaceStyle.maybeOf(context) == GlassSurfaceStyle.solid;
    final filled = active || prominent;
    final ink = active
        ? (glass ? tokens.accent : scheme.onPrimaryContainer)
        : prominent
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    final content = Padding(
      padding: _inset,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: height),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SvgIcon(icon, size: 16, color: ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: ink,
                  fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (!glass) {
      return Material(
        type: MaterialType.transparency,
        child: Ink(
          decoration: ShapeDecoration(
            color: filled ? scheme.primaryContainer : scheme.surfaceContainer,
            shape: filled
                ? _shape
                : _shape.copyWith(
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
          ),
          child: InkWell(
            customBorder: _shape,
            onTap: onTap,
            child: content,
          ),
        ),
      );
    }

    return GlassButton.custom(
      shape: _shape,
      onTap: onTap,
      enabled: true,
      label: semanticLabel ?? label,
      settings: solid
          ? null
          : tokens.control(
              tint: filled ? scheme.primary : null,
              strong: prominent,
              enabled: true,
            ),
      surfaceStyle: solid ? GlassSurfaceStyle.solid : null,
      quality: solid ? null : AppGlassTheme.controlQuality,
      color: solid
          ? (filled ? scheme.primaryContainer : scheme.surfaceContainerHigh)
          : null,
      interactionScale: tokens.reduceMotion ? 1 : .96,
      stretch: tokens.reduceMotion ? 0 : .2,
      anchorStretch: !tokens.reduceMotion,
      glowColor: filled ? scheme.primary : null,
      pressLightColor: filled ? scheme.primary : null,
      glowRadius: tokens.reduceMotion ? 0 : .9,
      child: content,
    );
  }
}
