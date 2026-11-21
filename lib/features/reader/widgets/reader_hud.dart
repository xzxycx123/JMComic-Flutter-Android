import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/ui/glass/app_glass.dart';
import '../reader_mode.dart';

/// Uses the reader's dark palette for glass controls and overlay launch sites.
class ReaderControlsTheme extends StatelessWidget {
  const ReaderControlsTheme({required this.child, super.key});

  static final ThemeData _dark = AppTheme.dark();
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(
        data: context.isLiquidGlass ? _dark : Theme.of(context),
        child: child,
      );
}

/// 阅读器 HUD：顶部 46（退出 / 标题页码 / 模式切换），底部 64（进度 / Slider / 百分比）。
class ReaderHud extends StatelessWidget {
  const ReaderHud({
    required this.title,
    required this.page,
    required this.total,
    required this.mode,
    required this.visible,
    required this.onExit,
    required this.onToggleMode,
    required this.onJump,
    super.key,
    this.onSliderChanged,
    this.lineLabel = '',
    this.onSwitchLine,
    this.switchingLine = false,
  });

  final String title;
  final int page;
  final int total;
  final ReaderMode mode;
  final bool visible;
  final VoidCallback onExit;
  final VoidCallback onToggleMode;
  final ValueChanged<int> onJump;
  final ValueChanged<double>? onSliderChanged;

  /// 当前分流标签（线路1..5）；为空或没有回调时不渲染分流按钮。
  final String lineLabel;
  final VoidCallback? onSwitchLine;
  final bool switchingLine;

  static final Color _barColor = AppColors.readerBg.withAlpha(230);
  static const Color _ink = AppColors.readerInk;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: visible ? 1 : 0),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          child: ReaderControlsTheme(child: Builder(builder: _buildBars)),
          builder: (context, opacity, child) {
            // Remove both bars after fading out so hidden glass does no work.
            if (opacity == 0) return const SizedBox.shrink();
            return Opacity(opacity: opacity, child: child);
          },
        ),
      );

  Widget _buildBars(BuildContext context) {
    final ratio = total <= 0 ? 0 : (page / total * 100).round();
    return Column(
      children: <Widget>[
        _bar(
          context,
          top: true,
          child: SizedBox(
            height: 46,
            child: Row(
              children: <Widget>[
                AppIconButton(
                  onPressed: onExit,
                  icon: const IconTheme(
                    data: IconThemeData(color: _ink),
                    child: SvgIcon(AppIcons.back, size: 22),
                  ),
                ),
                Expanded(
                  child: Text(
                    '$title · 第 $page/$total 页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: _ink),
                  ),
                ),
                if (onSwitchLine != null && lineLabel.isNotEmpty)
                  AppButton(
                    variant: context.isLiquidGlass
                        ? AppButtonVariant.secondary
                        : AppButtonVariant.text,
                    height: context.isLiquidGlass ? 44 : null,
                    onPressed: switchingLine ? null : onSwitchLine,
                    foregroundColor: _ink,
                    style: TextButton.styleFrom(
                      foregroundColor: _ink,
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: switchingLine
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: AppProgressIndicator.circular(
                              size: 14,
                              strokeWidth: 2,
                              color: _ink,
                            ),
                          )
                        : Text(
                            lineLabel,
                            style: AppTypography.micro.copyWith(color: _ink),
                          ),
                  ),
                AppIconButton(
                  tooltip: mode.toggled.label,
                  onPressed: onToggleMode,
                  icon: IconTheme(
                    data: const IconThemeData(color: _ink),
                    child: SvgIcon(mode.icon, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _bar(
          context,
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  Text(
                    '已读 $page/$total',
                    style: AppTypography.micro.copyWith(color: _ink),
                  ),
                  Expanded(
                    child: AppSlider(
                      value: page.clamp(1, total <= 0 ? 1 : total).toDouble(),
                      min: 1,
                      max: total <= 0 ? 1 : total.toDouble(),
                      onChanged: total <= 1
                          ? null
                          : (value) => onSliderChanged?.call(value),
                      onChangeEnd:
                          total <= 1 ? null : (value) => onJump(value.round()),
                      activeColor: _ink,
                      inactiveColor: _ink.withValues(alpha: 0.28),
                      thumbColor: _ink,
                    ),
                  ),
                  Text(
                    '$ratio%',
                    style: AppTypography.numeric.copyWith(color: _ink),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 顶部条颜色铺到状态栏底下，内容通过 SafeArea 避开状态栏。
  Widget _bar(BuildContext context, {required Widget child, bool top = false}) {
    final content = top ? SafeArea(bottom: false, child: child) : child;
    if (context.isLiquidGlass) {
      // The controls are already glass; the bar only tints the background.
      return AppGlassChrome(
        reader: true,
        metalColor: _barColor,
        child: content,
      );
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(color: _barColor),
          child: content,
        ),
      ),
    );
  }
}
