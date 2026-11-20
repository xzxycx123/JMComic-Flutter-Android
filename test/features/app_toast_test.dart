import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/ui/app_toast.dart';

/// 收藏提示（自绘 toast）必须**一定会自己消失**。
///
/// 之前用 SnackBar：它的自动消失依赖框架内部的 Timer，只有「当前路由 active 且动画完成」
/// 才启动，无障碍模式 / 弹层 / 路由切换下可能永不启动，表现就是一条黑条一直挂着。
void main() {
  testWidgets('AppToast 到时自动消失（带撤销按钮也一样）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => AppToast.show(
                  context,
                  '已收藏',
                  actionLabel: '撤销',
                  onAction: () {},
                ),
                child: const Text('收藏'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('收藏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('已收藏'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget);

    // 1600ms 基础 + 1400ms（带操作按钮）后必须自己消失。
    await tester.pump(const Duration(milliseconds: 3200));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('已收藏'), findsNothing);
    expect(find.text('撤销'), findsNothing);
  });

  testWidgets('连续两次提示只保留最新的那条', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(
                    onPressed: () => AppToast.show(context, '已收藏'),
                    child: const Text('a'),
                  ),
                  TextButton(
                    onPressed: () => AppToast.show(context, '已取消收藏'),
                    child: const Text('b'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('a'));
    await tester.pump();
    await tester.tap(find.text('b'));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('已收藏'), findsNothing);
    expect(find.text('已取消收藏'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2000));
    expect(find.text('已取消收藏'), findsNothing);
  });
}
