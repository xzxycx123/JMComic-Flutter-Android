import 'package:flutter/material.dart';

/// 左右翻页（电子书模式）：整屏一页，页面滑入滑出。
class PageTurnView extends StatelessWidget {
  const PageTurnView({
    required this.controller,
    required this.total,
    required this.itemBuilder,
    required this.onPageChanged,
    super.key,
    this.physics,
  });

  final PageController controller;
  final int total;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;

  /// 缩放中传 [NeverScrollableScrollPhysics]：把拖动让给图片平移。
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      itemCount: total,
      onPageChanged: (index) => onPageChanged(index + 1),
      allowImplicitScrolling: true,
      physics: physics,
      itemBuilder: (context, index) => itemBuilder(context, index),
    );
  }
}
