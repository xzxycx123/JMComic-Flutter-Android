import 'package:flutter/material.dart';

/// 点击三分区：左 30% 向前翻 / 中 40% 显示详情（HUD）/ 右 30% 向后翻。
///
/// 左右翻页与上下滚动共用同一套比例：一边是「上一页 / 下一页」，
/// 另一边是「上一屏 / 下一屏」，手指落点决定语义，换模式不换手感。
const double readerTapZoneEdgeRatio = .3;

/// 三分区语义（左右翻页与上下滚动共用）。
enum ReaderTapZone {
  /// 左侧：向前翻（上一页 / 上一屏）。
  previous,

  /// 中间：显示详情（HUD 进度条）。
  hud,

  /// 右侧：向后翻（下一页 / 下一屏）。
  next,
}

/// 按横向落点（[dx]，相对阅读区左边 / [width] 阅读区宽度）算三分区。
///
/// 竖读没有叠在滚动视图上的点击层（那会抢走结束页按钮的点击），
/// 由外层 `onTapUp` 拿落点进来查这张表，保证两种模式分区一致。
ReaderTapZone readerTapZoneAt(double dx, double width) {
  if (width <= 0) return ReaderTapZone.hud;
  final ratio = dx / width;
  if (ratio < readerTapZoneEdgeRatio) return ReaderTapZone.previous;
  if (ratio > 1 - readerTapZoneEdgeRatio) return ReaderTapZone.next;
  return ReaderTapZone.hud;
}

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
