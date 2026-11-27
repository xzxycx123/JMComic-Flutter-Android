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
    this.itemCount,
    this.footerExtent = 0,
    this.itemExtent,
  });

  final ScrollController controller;
  final int total;

  /// 列表项数量：默认等于 [total]；阅读器会在末尾多挂一个「结束页」。
  ///
  /// 页码估算始终按 [total] 算，多出来的末尾项不会被当成正文页。
  final int? itemCount;

  /// 末尾结束页的固定高度（逻辑像素）。
  ///
  /// 页码比例按「正文可滚动高度 = maxScrollExtent - footerExtent」计算，
  /// 这样结束页不会被折算成一个额外的正文页；滚到结束页时页码稳定停在 total。
  final double footerExtent;

  /// PDF 每页占一个视口，使尚未渲染的页面也有确定的滚动位置。
  final double? itemExtent;

  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;

  /// 缩放中传 [NeverScrollableScrollPhysics]：避免双指拖动同时翻页。
  final ScrollPhysics? physics;

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || total <= 1) return false;
    final contentExtent = math.max(
      0.0,
      notification.metrics.maxScrollExtent - footerExtent,
    );
    if (contentExtent <= 0) return false;
    final ratio = (notification.metrics.pixels / contentExtent).clamp(0.0, 1.0);
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
        itemCount: itemCount ?? total,
        itemExtent: itemExtent,
        physics: physics ?? const ClampingScrollPhysics(),
        itemBuilder: (context, index) => itemBuilder(context, index),
      ),
    );
  }
}
