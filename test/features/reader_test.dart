import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/features/reader/reader_mode.dart';
import 'package:jm_comic/features/reader/widgets/reader_hud.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

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
    testWidgets('顶部条避开系统状态栏（padding.top）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 28)),
            child: Scaffold(
              body: SizedBox(
                height: 500,
                child: ReaderHud(
                  title: '测试',
                  page: 1,
                  total: 2,
                  mode: ReaderMode.paged,
                  visible: true,
                  onExit: () {},
                  onToggleMode: () {},
                  onJump: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final titleRect = tester.getRect(find.textContaining('第 1/2 页'));
      expect(
        titleRect.top,
        greaterThanOrEqualTo(28),
        reason: 'HUD 文字必须在状态栏之下，不能与时间/信号图标重叠',
      );
    });

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

    testWidgets('玻璃进度条预览、松手跳页、点击跳页及隐藏', (tester) async {
      final previews = <double>[];
      final jumps = <int>[];
      var page = 12;
      var visible = true;
      var underlyingTaps = 0;
      late StateSetter rebuild;

      await tester.pumpWidget(
        LiquidGlassWidgets.wrap(
          theme: const GlassThemeData.ios27(),
          brightnessResolver: Theme.maybeBrightnessOf,
          child: MaterialApp(
            theme: ThemeData.light(),
            home: InterfaceStyleScope(
              style: AppInterfaceStyle.liquidGlass,
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    rebuild = setState;
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => underlyingTaps++,
                        ),
                        ReaderHud(
                          title: '玻璃阅读器',
                          page: page,
                          total: 20,
                          mode: ReaderMode.paged,
                          visible: visible,
                          onExit: () {},
                          onToggleMode: () {},
                          onSliderChanged: (value) {
                            previews.add(value);
                            setState(() => page = value.round());
                          },
                          onJump: jumps.add,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final slider = find.byType(GlassSlider);
      expect(slider, findsOneWidget);
      expect(Theme.of(tester.element(slider)).brightness, Brightness.dark);
      final track = tester.getRect(slider);
      final confinement =
          find.ancestor(of: slider, matching: find.byType(ClipRect));
      expect(confinement, findsOneWidget);
      final paintBounds = tester.getRect(confinement);
      expect(tester.widget<ClipRect>(confinement).clipBehavior, Clip.hardEdge);
      expect(paintBounds.left,
          greaterThanOrEqualTo(tester.getRect(find.text('已读 12/20')).right),);
      expect(paintBounds.right,
          lessThanOrEqualTo(tester.getRect(find.text('60%')).left),);
      expect(track.left, greaterThan(paintBounds.left));
      final gesture = await tester.startGesture(track.center);
      await gesture.moveBy(Offset(-track.width * .25, 0));
      await gesture.moveBy(Offset(-track.width * .5, 0));
      await tester.pump(const Duration(milliseconds: 175));
      expect(find.text('已读 1/20'), findsOneWidget);
      expect(tester.getRect(slider), track);
      await gesture.moveTo(track.center + const Offset(80, 0));
      await tester.pump();
      expect(previews, isNotEmpty);
      expect(jumps, isEmpty);
      expect(find.text('已读 $page/20'), findsOneWidget);

      // Release without pumping the last preview into GlassSlider.value.
      final builtValue = tester.widget<GlassSlider>(slider).value;
      await gesture.moveBy(const Offset(85, 0));
      final endPage = previews.last.round();
      expect(endPage, greaterThan(builtValue));
      expect(jumps, isEmpty);
      await gesture.up();
      expect(jumps, [endPage]);

      final endOfTrack = Offset(track.right - 1, track.center.dy);
      await tester.tapAt(endOfTrack);
      expect(previews.last.round(), 20);
      expect(jumps, [endPage, 20]);
      expect(underlyingTaps, 0);

      rebuild(() => visible = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(slider, findsNothing);
      expect(find.textContaining('玻璃阅读器'), findsNothing);
      await tester.tapAt(endOfTrack);
      expect(underlyingTaps, 1);
      expect(jumps, [endPage, 20]);
    });

    testWidgets('玻璃线路按钮展开浮层，返回键先关闭浮层', (tester) async {
      final changes = <bool>[];
      var selected = 0;
      await tester.pumpWidget(
        LiquidGlassWidgets.wrap(
          child: MaterialApp(
            home: InterfaceStyleScope(
              style: AppInterfaceStyle.liquidGlass,
              child: Scaffold(
                body: ReaderHud(
                  title: '阅读器',
                  page: 1,
                  total: 10,
                  mode: ReaderMode.paged,
                  visible: true,
                  lineLabel: '线路2',
                  glassPickerBuilder: (context, close) => Material(
                    type: MaterialType.transparency,
                    child: TextButton(
                      onPressed: () {
                        selected++;
                        close();
                      },
                      child: const Text('选择线路3'),
                    ),
                  ),
                  onGlassPickerOpenChanged: changes.add,
                  onExit: () {},
                  onToggleMode: () {},
                  onJump: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      final lineLabel = find.text('线路2');
      final trigger = find.ancestor(
        of: lineLabel,
        matching: find.byType(GlassButton),
      );
      expect(tester.widget<GlassButton>(trigger).shape,
          const LiquidRoundedSuperellipse(borderRadius: 9),);
      expect(tester.getSize(trigger).height, lessThan(40));
      for (final icon
          in tester.widgetList<GlassIconButton>(find.byType(GlassIconButton))) {
        expect(icon.size, 34);
      }
      await tester.tap(lineLabel);
      await tester.pumpAndSettle();
      expect(find.text('选择线路3'), findsOneWidget);
      expect(changes, [true]);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(await navigator.maybePop(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('选择线路3'), findsNothing);
      expect(lineLabel, findsOneWidget);
      expect(changes, [true, false]);
      await tester.tap(lineLabel);
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择线路3'));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(changes, [true, false, true, false]);
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
