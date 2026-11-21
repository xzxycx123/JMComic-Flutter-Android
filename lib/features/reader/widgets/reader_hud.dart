import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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

typedef ReaderHudPickerBuilder = Widget Function(
  BuildContext context,
  VoidCallback close,
);

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
    this.onSliderCancel,
    this.lineLabel = '',
    this.onSwitchLine,
    this.switchingLine = false,
    this.glassPickerBuilder,
    this.glassPickerHeight = 160,
    this.onGlassPickerOpenChanged,
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
  final VoidCallback? onSliderCancel;
  final String lineLabel;
  final VoidCallback? onSwitchLine;
  final bool switchingLine;
  final ReaderHudPickerBuilder? glassPickerBuilder;
  final double glassPickerHeight;
  final ValueChanged<bool>? onGlassPickerOpenChanged;

  static const Color _ink = AppColors.readerInk;

  /// 顶 / 底浮动条的圆角矩形灰底（Metal 与 LiquidGlass 两套皮肤一致）。
  static const Color barColor = Color(0xE6333335);
  static const double barRadius = 18;

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
            if (opacity == 0) return const SizedBox.shrink();
            return Opacity(opacity: opacity, child: child);
          },
        ),
      );

  Widget _buildBars(BuildContext context) {
    final ratio = total <= 0 ? 0 : (page / total * 100).round();
    final glass = context.isLiquidGlass;
    return Column(
      children: <Widget>[
        _bar(
          top: true,
          child: SizedBox(
            height: 46,
            child: Row(
              children: <Widget>[
                AppIconButton(
                  onPressed: onExit,
                  tooltip: glass ? '返回' : null,
                  glassSize: 34,
                  icon: SvgIcon(
                    AppIcons.back,
                    size: glass ? 16 : 22,
                    color: _ink,
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
                if (lineLabel.isNotEmpty &&
                    (onSwitchLine != null ||
                        (glass && glassPickerBuilder != null))) ...<Widget>[
                  _lineControl(context),
                  // 和右侧「切换阅读模式」拉开距离，别挤在一起。
                  const SizedBox(width: 10),
                ],
                AppIconButton(
                  tooltip: mode.toggled.label,
                  onPressed: onToggleMode,
                  glassSize: 34,
                  icon: SvgIcon(mode.icon, size: glass ? 16 : 20, color: _ink),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        _bar(
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 16),
                  _progressText(
                    context,
                    '已读 $page/$total',
                    '已读 $total/$total',
                    AppTypography.micro,
                  ),
                  Expanded(
                    child: AppSlider(
                      value: page.clamp(1, total <= 0 ? 1 : total).toDouble(),
                      min: 1,
                      max: total <= 0 ? 1 : total.toDouble(),
                      confineGlassThumb: glass,
                      onGlassDragCancel: onSliderCancel,
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
                  _progressText(
                    context,
                    '$ratio%',
                    '100%',
                    AppTypography.numeric,
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

  Widget _progressText(
    BuildContext context,
    String value,
    String widest,
    TextStyle style,
  ) {
    final ink = style.copyWith(
      color: _ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (!context.isLiquidGlass) return Text(value, style: ink);
    final painter = TextPainter(
      text: TextSpan(text: widest, style: ink),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return SizedBox(
      width: width,
      child:
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: ink),
    );
  }

  Widget _lineControl(BuildContext context) {
    final content = switchingLine
        ? const AppProgressIndicator.circular(
            size: 14,
            strokeWidth: 2,
            color: _ink,
          )
        : Text(lineLabel, style: AppTypography.micro.copyWith(color: _ink));
    if (!context.isLiquidGlass) {
      return AppButton.text(
        onPressed: switchingLine ? null : onSwitchLine,
        foregroundColor: _ink,
        style: TextButton.styleFrom(
          foregroundColor: _ink,
          // 药丸形按钮（Metal 皮肤下只是触点/水波形状）。
          shape: const StadiumBorder(),
          minimumSize: const Size(0, 34),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: content,
      );
    }
    Widget trigger(BuildContext context, VoidCallback onTap) {
      final theme = AppGlassTheme.of(context);
      return GlassButton.custom(
        label: lineLabel,
        onTap: onTap,
        enabled: !switchingLine,
        height: 34,
        // 药丸（全圆角）而不是小圆角方块。
        shape:
            const LiquidRoundedSuperellipse(borderRadius: AppColors.radiusPill),
        quality: AppGlassTheme.controlQuality,
        settings: theme.control(enabled: !switchingLine),
        interactionScale: theme.reduceMotion ? 1 : .96,
        stretch: theme.reduceMotion ? 0 : .16,
        anchorStretch: !theme.reduceMotion,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(widthFactor: 1, child: content),
          ),
        ),
      );
    }

    final builder = glassPickerBuilder;
    if (builder == null) return trigger(context, () => onSwitchLine?.call());
    return _ReaderHudPicker(
      triggerBuilder: trigger,
      contentBuilder: builder,
      height: glassPickerHeight,
      onOpenChanged: onGlassPickerOpenChanged,
    );
  }

  /// 顶栏 / 底栏 = 圆角矩形灰底 + 浮动控件。
  ///
  /// 两套皮肤都用同一块灰底（不做玻璃折射、不做背景模糊），
  /// 顶栏仍然套 SafeArea 避开状态栏；底栏的安全区由内容自己处理。
  Widget _bar({required Widget child, bool top = false}) {
    final content = top ? SafeArea(bottom: false, child: child) : child;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, top ? 6 : 0, 12, top ? 0 : 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(barRadius),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: content,
        ),
      ),
    );
  }
}

class _ReaderHudPicker extends StatefulWidget {
  const _ReaderHudPicker({
    required this.triggerBuilder,
    required this.contentBuilder,
    required this.height,
    this.onOpenChanged,
  });

  final Widget Function(BuildContext, VoidCallback) triggerBuilder;
  final ReaderHudPickerBuilder contentBuilder;
  final double height;
  final ValueChanged<bool>? onOpenChanged;

  @override
  State<_ReaderHudPicker> createState() => _ReaderHudPickerState();
}

class _ReaderHudPickerState extends State<_ReaderHudPicker> {
  final _controller = GlassPopoverController();
  LocalHistoryEntry? _history;

  void _open() {
    final route = ModalRoute.of(context);
    if (route != null && _history == null) {
      final entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_history == null) return;
          _history = null;
          _controller.close();
        },
      );
      _history = entry;
      route.addLocalHistoryEntry(entry);
    }
    widget.onOpenChanged?.call(true);
  }

  void _removeHistory() {
    final entry = _history;
    _history = null;
    entry?.remove();
  }

  void _close() {
    _removeHistory();
    widget.onOpenChanged?.call(false);
  }

  @override
  void dispose() {
    _removeHistory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppGlassTheme.of(context);
    final size = MediaQuery.sizeOf(context);
    final safeArea = MediaQuery.viewPaddingOf(context);
    final maxHeight = (size.height - safeArea.vertical - 24).clamp(1.0, 336.0);
    return GlassPopover(
      controller: _controller,
      triggerBuilder: widget.triggerBuilder,
      contentBuilder: widget.contentBuilder,
      popoverWidth: (size.width - safeArea.horizontal - 24).clamp(1.0, 288.0),
      popoverHeight: widget.height.clamp(1.0, maxHeight),
      popoverBorderRadius: 20,
      settings: theme.overlay,
      quality: GlassQuality.premium,
      enableInteractionGlow: !theme.reduceMotion,
      onOpen: _open,
      onClose: _close,
    );
  }
}
