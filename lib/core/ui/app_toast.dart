import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// 自绘轻提示（底部小胶囊），**不依赖 SnackBar 的计时器**。
///
/// 为什么不用 `ScaffoldMessenger.showSnackBar`：
/// Flutter 的 SnackBar 只有在「当前路由是 active 且动画已完成」时才启动自动消失的
/// `Timer`（`ScaffoldMessengerState.build` 里那段逻辑），无障碍模式 / 弹出层 / 路由
/// 切换都可能让计时器根本启动不了——表现在用户眼里就是「黑条永远挂在那儿」。
/// 这里用 Overlay + 自己的 Timer，插入与移除都在我们手里，1.6s 后必然消失。
class AppToast {
  AppToast._();

  static OverlayEntry? _entry;
  static Timer? _timer;
  static int _token = 0;

  /// [actionLabel] 非空时多停留一会儿（给人点「撤销」的机会）。
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
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

    final entry = OverlayEntry(
      builder: (overlayContext) => _ToastBubble(
        message: message,
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
    overlay.insert(entry);
    _timer = Timer(hold, () {
      if (token == _token) dismiss();
    });
  }

  static void dismiss() {
    _timer?.cancel();
    _timer = null;
    final entry = _entry;
    _entry = null;
    if (entry == null) return;
    try {
      entry.remove();
    } catch (_) {
      // 已被框架移除（例如 Overlay 销毁）时忽略。
    }
  }
}

class _ToastBubble extends StatefulWidget {
  const _ToastBubble({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  State<_ToastBubble> createState() => _ToastBubbleState();
}

class _ToastBubbleState extends State<_ToastBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 160),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 24,
      right: 24,
      bottom: bottomInset + 96,
      child: IgnorePointer(
        ignoring: false,
        child: FadeTransition(
          opacity: _controller,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.25),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
            ),
            child: Center(
              child: Material(
                color: Colors.transparent,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 360),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    10,
                    widget.actionLabel == null ? 16 : 8,
                    10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightInk.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(AppColors.radiusPill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.darkInk,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null) ...<Widget>[
                        const SizedBox(width: 6),
                        TextButton(
                          onPressed: widget.onAction,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.darkPrimary,
                            minimumSize: const Size(0, 32),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            textStyle: AppTypography.caption,
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
    );
  }
}
