import 'package:flutter/material.dart';

/// 左右翻页模式的点击三分区：左 30% 上一页 / 中 40% HUD / 右 30% 下一页。
///
/// 用 [HitTestBehavior.translucent] 叠在图片层上，保证双指缩放与拖动仍然生效；
/// 缩放中（[enabled] 为 false）只禁用单击，双击缩放仍然可用（否则放大后没路退出）。
/// 双击只挂在中间区：挂在三个区会让每次单击都要等 300ms 的双击判定，翻页会明显变钝。
class ReaderTapZones extends StatelessWidget {
  const ReaderTapZones({
    required this.child,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleHud,
    super.key,
    this.onDoubleTap,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleHud;
  final VoidCallback? onDoubleTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final zones = Row(
      children: <Widget>[
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: enabled ? onPrevious : null,
          ),
        ),
        Expanded(
          flex: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: enabled ? onToggleHud : null,
            onDoubleTap: onDoubleTap,
          ),
        ),
        Expanded(
          flex: 3,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: enabled ? onNext : null,
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        child,
        Positioned.fill(child: zones),
      ],
    );
  }
}
