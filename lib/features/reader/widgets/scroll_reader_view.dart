import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 上下滚动（条漫模式）：纵向连续拼页，按滚动比例估算当前页。
class ScrollReaderView extends StatelessWidget {
  const ScrollReaderView({
    required this.controller,
    required this.total,
    required this.itemBuilder,
    required this.onPageChanged,
    super.key,
    this.physics,
  });

  final ScrollController controller;
  final int total;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;

  /// 缩放中传 [NeverScrollableScrollPhysics]：避免双指拖动同时翻页。
  final ScrollPhysics? physics;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || total <= 1) return false;
    final max = notification.metrics.maxScrollExtent;
    if (max <= 0) return false;
    final ratio = (notification.metrics.pixels / max).clamp(0.0, 1.0);
    final page = (ratio * (total - 1)).round() + 1;
    onPageChanged(math.min(math.max(page, 1), total));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: controller,
        itemCount: total,
        physics: physics ?? const ClampingScrollPhysics(),
        itemBuilder: (context, index) => itemBuilder(context, index),
      ),
    );
  }
}
