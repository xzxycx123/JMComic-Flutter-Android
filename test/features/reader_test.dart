import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_colors.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/ui/glass/app_glass.dart';
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
      expect(
        paintBounds.left,
        greaterThanOrEqualTo(tester.getRect(find.text('已读 12/20')).right),
      );
      expect(
        paintBounds.right,
        lessThanOrEqualTo(tester.getRect(find.text('60%')).left),
      );
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
      expect(
        tester.widget<GlassButton>(trigger).shape,
        const LiquidRoundedSuperellipse(borderRadius: AppColors.radiusPill),
        reason: '分流节点是药丸（全圆角），不是小圆角方块',
      );
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
      // 分流（节点）与右侧「切换阅读模式」之间留了间距，不许贴在一起。
      final lineButton = find.byType(TextButton);
      final modeButton = find.byType(AppIconButton).last;
      expect(
        tester.getRect(lineButton).right + 8,
        lessThanOrEqualTo(tester.getRect(modeButton).left),
        reason: '节点按钮与模式按钮至少要隔开 8px',
      );
      await tester.tap(find.text('线路2'));
      expect(switched, 1);
    });

    /// 底栏的圆角矩形灰底。
    Finder greyBar() => find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  ReaderHud.barColor &&
              (widget.decoration as BoxDecoration).borderRadius ==
                  BorderRadius.circular(ReaderHud.barRadius),
        );

    /// 顶部底板：从屏幕顶边铺下来，顶边直角、只有底边圆角。
    Finder topPlate() => find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).color ==
                  ReaderHud.barColor &&
              (widget.decoration as BoxDecoration).borderRadius ==
                  ReaderHud.topPlateRadius,
        );

    testWidgets('顶部底板铺到状态栏后面：顶边贴屏幕顶边、顶边直角、控件在 inset 下、不吃点击', (tester) async {
      var underlyingTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              padding: EdgeInsets.only(top: 24),
              viewPadding: EdgeInsets.only(top: 24),
            ),
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => underlyingTaps++,
                  ),
                  ReaderHud(
                    title: '阅读器',
                    page: 1,
                    total: 10,
                    mode: ReaderMode.paged,
                    visible: true,
                    onExit: () {},
                    onToggleMode: () {},
                    onJump: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      final plateRect = tester.getRect(topPlate());
      expect(plateRect.top, 0, reason: '底板必须从屏幕顶边延伸，不能留 6px 缝');
      expect(plateRect.left, 0);
      expect(
        plateRect.right,
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
      );
      expect(
        plateRect.height,
        ReaderHud.topPlateHeightOf(
          const MediaQueryData(
            padding: EdgeInsets.only(top: 24),
            viewPadding: EdgeInsets.only(top: 24),
          ),
        ),
      );
      final radius =
          (tester.widget<DecoratedBox>(topPlate()).decoration as BoxDecoration)
              .borderRadius! as BorderRadius;
      expect(radius.topLeft, Radius.zero, reason: '顶边直角，不再顶一块 18px 圆角灰板');
      expect(radius.bottomLeft, const Radius.circular(ReaderHud.barRadius));

      // 控件落在状态栏（top inset）以下，不会压住系统时间 / 电量。
      expect(
        tester.getRect(find.text('阅读器 · 第 1/10 页')).top,
        greaterThanOrEqualTo(24),
      );

      // 状态栏那条带子只是背景：底板不拦截触摸，点击漏给阅读区。
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(size.width / 2, 10));
      expect(underlyingTaps, 1, reason: '状态栏背景必须让点击穿透');
    });

    testWidgets('沉浸式（padding=0、viewPadding 有额头）时控件照样落在额头之下', (tester) async {
      var underlyingTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(top: 28),
            ),
            child: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => underlyingTaps++,
                  ),
                  ReaderHud(
                    title: '阅读器',
                    page: 1,
                    total: 10,
                    mode: ReaderMode.paged,
                    visible: true,
                    onExit: () {},
                    onToggleMode: () {},
                    onJump: (_) {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(
        tester.getRect(topPlate()).height,
        28 + ReaderHud.topRowHeight + ReaderHud.topPlateLip,
        reason: '沉浸式下 viewPadding 才是屏幕真实额头',
      );
      expect(
        tester.getRect(find.text('阅读器 · 第 1/10 页')).top,
        greaterThanOrEqualTo(28),
      );
      final size = tester.view.physicalSize / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(size.width / 2, 10));
      expect(underlyingTaps, 1);
    });

    testWidgets('没有状态栏 inset 时顶部底板只有控件行高度，不会顶出一条空条', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
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
      );
      await tester.pump(const Duration(milliseconds: 200));

      final plateRect = tester.getRect(topPlate());
      expect(plateRect.top, 0);
      expect(
        plateRect.height,
        ReaderHud.topRowHeight + ReaderHud.topPlateLip,
        reason: 'inset 为 0 时底板只到控件行下面的 6px 底边',
      );
      final titleRect = tester.getRect(find.text('测试 · 第 1/2 页'));
      expect(titleRect.top, greaterThanOrEqualTo(0));
      expect(
        titleRect.bottom,
        lessThanOrEqualTo(ReaderHud.topRowHeight),
        reason: '控件行紧贴屏幕顶边，底板不会多出一条空带',
      );
      expect(find.textContaining('已读 1/2'), findsOneWidget);
    });

    testWidgets('给了 onMore 就只留一个「更多」按钮（翻页方式 + 节点都收进去）', (tester) async {
      var moreTaps = 0;
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
                onMore: () => moreTaps++,
                onExit: () {},
                onToggleMode: () {},
                onJump: (_) {},
              ),
            ),
          ),
        ),
      );

      // 只剩「退出」和「更多」两个图标按钮，节点药丸与模式按钮都不再单独出现。
      expect(find.byType(AppIconButton), findsNWidgets(2));
      expect(find.text('线路2'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is SvgIcon && widget.asset == AppIcons.more,
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(AppIconButton).last);
      expect(moreTaps, 1);
    });

    testWidgets('顶栏 / 底栏是圆角矩形灰底，不再铺玻璃板或模糊遮罩', (tester) async {
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

      expect(topPlate(), findsOneWidget, reason: '顶部是一块从屏幕顶边铺下来的底板');
      expect(greyBar(), findsOneWidget, reason: '下面只剩底栏一条圆角灰底');
      expect(
        find.byType(BackdropFilter),
        findsNothing,
        reason: 'Metal 皮肤不做模糊遮罩',
      );
      expect(find.byType(AppGlassChrome), findsNothing);
    });

    testWidgets('玻璃皮肤下顶栏 / 底栏也是圆角矩形灰底', (tester) async {
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
                  onExit: () {},
                  onToggleMode: () {},
                  onJump: (_) {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(topPlate(), findsOneWidget, reason: '玻璃皮肤同样用同一块顶部底板');
      expect(greyBar(), findsOneWidget, reason: '底栏仍是圆角灰底');
      expect(find.byType(AppGlassChrome), findsNothing, reason: 'HUD 条不铺玻璃板');
      expect(find.text('已读 1/10'), findsOneWidget);
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
