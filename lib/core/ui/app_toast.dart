import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 自绘轻提示（底部细胶囊），**不依赖 SnackBar 的计时器**。
///
/// 为什么不用 `ScaffoldMessenger.showSnackBar`：
/// Flutter 的 SnackBar 只有在「当前路由是 active 且动画已完成」时才启动自动消失的
/// `Timer`（`ScaffoldMessengerState.build` 里那段逻辑），无障碍模式 / 弹出层 / 路由
/// 切换都可能让计时器根本启动不了——表现在用户眼里就是「黑条永远挂在那儿」。
/// 这里用 Overlay + 自己的 Timer，插入与移除都在我们手里，1.6s 后必然消失。
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static GlobalKey<_ToastBubbleState>? _bubbleKey;
  static Timer? _timer;
  static int _token = 0;

  /// [actionLabel] 非空时多停留一会儿（给人点「撤销」的机会）。
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    IconData? icon,
    Duration duration = const Duration(milliseconds: 1600),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return;

    dismiss();
    final token = ++_token;
    final hold = actionLabel == null
        ? duration
        : duration + const Duration(milliseconds: 1400);

    final key = GlobalKey<_ToastBubbleState>();
    final entry = OverlayEntry(
      builder: (_) => _ToastBubble(
        key: key,
        message: message,
        icon: icon,
        actionLabel: actionLabel,
        onAction: actionLabel == null
            ? null
            : () {
                onAction?.call();
                dismiss();
              },
      ),
    );

    _entry = entry;
    _bubbleKey = key;
    overlay.insert(entry);

    _timer = Timer(hold, () {
      if (token == _token) dismiss();
    });
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;

    final entry = _entry;
    final state = _bubbleKey?.currentState;
    _entry = null;
    _bubbleKey = null;
    if (entry == null) return;

    // 有 state 就播完退场动画再移除，避免「啪」地一下消失。
    if (state != null) {
      state.dismiss().whenComplete(() {
        try {
          entry.remove();
        } catch (_) {
          // 已被框架移除（例如 Overlay 销毁）时忽略。
        }
      });
      return;
    }

    try {
      entry.remove();
    } catch (_) {
      // 同上。
    }
  }
}

class _ToastBubble extends StatefulWidget {
  const _ToastBubble({
    super.key,
    required this.message,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    reverseDuration: const Duration(milliseconds: 160),
  );

  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
    reverseCurve: Curves.easeIn,
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.3),
    end: Offset.zero,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ),
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).animate(
    CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeIn,
    ),
  );

  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  /// 播放退场动画，调用方在完成后移除 OverlayEntry。
  Future<void> dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    try {
      await _controller.reverse();
    } catch (_) {
      // Ticker 在 dispose 后会被取消，忽略即可。
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final hasAction = widget.actionLabel != null;
    final hasIcon = widget.icon != null;

    return Positioned(
      left: 24,
      right: 24,
      bottom: bottomInset + 88,
      child: IgnorePointer(
        // 没有操作按钮时让点击穿透，别挡住下面的内容。
        ignoring: !hasAction,
        child: Center(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: ScaleTransition(
                scale: _scale,
                child: Semantics(
                  liveRegion: true,
                  container: true,
                  child: Material(
                    color: Colors.transparent,
                    child: ConstrainedBox(
                      // 窄一点，细长条更显轻。
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 20,
                              spreadRadius: -4,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                            child: Container(
                              // 关键：垂直 padding 收到 7，单行总高 ≈ 28。
                              padding: EdgeInsets.fromLTRB(
                                hasIcon ? 14 : 16,
                                7,
                                hasAction ? 6 : 16,
                                7,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.lightInk.withValues(alpha: 0.90),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  if (hasIcon) ...<Widget>[
                                    Icon(
                                      widget.icon,
                                      size: 14,
                                      color: AppColors.darkPrimary,
                                    ),
                                    const SizedBox(width: 7),
                                  ],
                                  Flexible(
                                    child: Text(
                                      widget.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      // 行高 1.15，两行时也不会把胶囊撑胖。
                                      style: AppTypography.caption.copyWith(
                                        color: AppColors.darkInk,
                                        height: 1.15,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.1,
                                      ),
                                    ),
                                  ),
                                  if (hasAction) ...<Widget>[
                                    const SizedBox(width: 6),
                                    TextButton(
                                      onPressed: widget.onAction,
                                      style: TextButton.styleFrom(
                                        foregroundColor:
                                            AppColors.darkPrimary,
                                        backgroundColor: AppColors.darkPrimary
                                            .withValues(alpha: 0.15),
                                        minimumSize: Size.zero,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 5,
                                        ),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        shape: const StadiumBorder(),
                                        textStyle:
                                            AppTypography.caption.copyWith(
                                          fontSize: 11,
                                          height: 1.1,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      child: Text(widget.actionLabel!),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}