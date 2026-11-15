import 'package:flutter/material.dart';

/// 左右翻页模式的点击三分区：左 30% 上一页 / 中 40% HUD / 右 30% 下一页。
///
/// 用 [HitTestBehavior.translucent] 叠在图片层上，保证双指缩放与拖动仍然生效；
/// 缩放中（[enabled] 为 false）时整块忽略指针，避免拖动误翻页。
class ReaderTapZones extends StatelessWidget {
  const ReaderTapZones({
    required this.child,
    required this.onPrevious,
    required this.onNext,
    required this.onToggleHud,
    super.key,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToggleHud;
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
        if (enabled) Positioned.fill(child: zones),
      ],
    );
  }
}
