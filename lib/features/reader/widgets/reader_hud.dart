import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/icons/app_icons.dart';
import '../../../core/theme/app_typography.dart';
import '../reader_mode.dart';

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

  static const Color _barColor = Color(0xE60B0B0A);
  static const Color _ink = Color(0xFFFAF9F5);

  @override
  Widget build(BuildContext context) {
    final ratio = total <= 0 ? 0 : (page / total * 100).round();
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: visible ? 1 : 0,
        child: Column(
          children: <Widget>[
            _bar(
              top: true,
              child: SizedBox(
                height: 46,
                child: Row(
                  children: <Widget>[
                    IconButton(
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
                      TextButton(
                        onPressed: switchingLine ? null : onSwitchLine,
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _ink,
                                ),
                              )
                            : Text(
                                lineLabel,
                                style:
                                    AppTypography.micro.copyWith(color: _ink),
                              ),
                      ),
                    IconButton(
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
                        child: Slider(
                          value:
                              page.clamp(1, total <= 0 ? 1 : total).toDouble(),
                          min: 1,
                          max: total <= 0 ? 1 : total.toDouble(),
                          onChanged: total <= 1
                              ? null
                              : (value) => onSliderChanged?.call(value),
                          onChangeEnd: total <= 1
                              ? null
                              : (value) => onJump(value.round()),
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
        ),
      ),
    );
  }

  /// 顶部条必须避开系统状态栏：颜色铺到状态栏底下，内容用 SafeArea 下移，
  /// 否则阅读器里 HUD 的返回键/标题会和状态栏时间、信号图标重叠。
  Widget _bar({required Widget child, bool top = false}) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: _barColor),
          child: top ? SafeArea(bottom: false, child: child) : child,
        ),
      ),
    );
  }
}
