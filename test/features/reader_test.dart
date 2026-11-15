import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/widgets/reader_hud.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';

void main() {
  group('ReaderMode / ReaderArgs', () {
    test('模式切换与默认值', () {
      expect(ReaderMode.fromCode(null), ReaderMode.paged);
      expect(ReaderMode.fromCode('vertical'), ReaderMode.vertical);
      expect(ReaderMode.paged.toggled, ReaderMode.vertical);
      expect(ReaderMode.vertical.toggled, ReaderMode.paged);
    });

    test('从路由 query 解析并回写', () {
      final args = ReaderArgs.fromQuery(<String, String>{
        'album': '350234',
        'chapter': '350234',
        'title': '全一话',
        'page': '12',
      });
      expect(args.albumId, '350234');
      expect(args.page, 12);
      expect(args.toQuery()['page'], '12');
      expect(args.route.startsWith('/reader?'), isTrue);
    });
  });

  group('ReaderTapZones（三分区点击）', () {
    testWidgets('左中右分别触发上一页 / HUD / 下一页', (tester) async {
      var previous = 0;
      var next = 0;
      var hud = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTapZones(
              onPrevious: () => previous++,
              onNext: () => next++,
              onToggleHud: () => hud++,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(ReaderTapZones));
      await tester.tapAt(Offset(rect.left + rect.width * 0.1, rect.center.dy));
      expect(previous, 1);

      await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
      expect(hud, 1);

      await tester.tapAt(Offset(rect.left + rect.width * 0.9, rect.center.dy));
      expect(next, 1);
    });

    testWidgets('缩放中（enabled=false）不响应分区点击', (tester) async {
      var previous = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderTapZones(
              enabled: false,
              onPrevious: () => previous++,
              onNext: () {},
              onToggleHud: () {},
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      );

      final rect = tester.getRect(find.byType(ReaderTapZones));
      await tester.tapAt(Offset(rect.left + rect.width * 0.1, rect.center.dy));
      expect(previous, 0);
    });
  });

  group('ReaderHud', () {
    testWidgets('显示页码与百分比，拖动回调触发', (tester) async {
      var jumped = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ReaderHud(
                title: '测试',
                page: 12,
                total: 19,
                mode: ReaderMode.paged,
                visible: true,
                onExit: () {},
                onToggleMode: () {},
                onJump: (page) => jumped = page,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('第 12/19 页'), findsOneWidget);
      expect(find.textContaining('已读 12/19'), findsOneWidget);
      expect(find.text('63%'), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(jumped, greaterThan(12));
    });

    testWidgets('顶栏显示当前分流并可点击切换', (tester) async {
      var switched = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ReaderHud(
                title: '测试',
                page: 1,
                total: 10,
                mode: ReaderMode.paged,
                visible: true,
                lineLabel: '线路2',
                onSwitchLine: () => switched++,
                onExit: () {},
                onToggleMode: () {},
                onJump: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('线路2'), findsOneWidget);
      await tester.tap(find.text('线路2'));
      expect(switched, 1);
    });

    testWidgets('没有回调时不渲染分流按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: ReaderHud(
                title: '测试',
                page: 1,
                total: 10,
                mode: ReaderMode.paged,
                visible: true,
                onExit: () {},
                onToggleMode: () {},
                onJump: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('线路2'), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });
  });
}
