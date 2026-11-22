import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_segmented_control.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/features/download/download_page.dart';
import 'package:jm_comic/features/download/download_providers.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _metalHost(Widget child, {double width = 328}) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

Widget _glassHost(
  Widget child, {
  double width = 328,
  bool disableAnimations = false,
}) =>
    LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, navigator) => InterfaceStyleScope(
          style: AppInterfaceStyle.liquidGlass,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: navigator!,
          ),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );

/// 筛选条内部（不含页面其它部分）的横向可滚动量：>0 表示可滑动。
double _maxScrollExtent(WidgetTester tester) {
  final states = tester.stateList<ScrollableState>(
    find.descendant(
      of: find.byType(DownloadFilterBar),
      matching: find.byType(Scrollable),
    ),
  );
  expect(states, isNotEmpty);
  return states.first.position.maxScrollExtent;
}

/// 「全部」与「已完成」的中点，应与筛选条水平中心重合（等宽分段 = 居中）。
void _expectCentered(WidgetTester tester) {
  final bar = tester.getRect(find.byType(DownloadFilterBar));
  final first = tester.getCenter(find.text('全部'));
  final last = tester.getCenter(find.text('已完成'));
  expect((first.dx + last.dx) / 2, closeTo(bar.center.dx, 1.5));
}

void main() {
  testWidgets('宽度够时分段等宽居中铺满，且不可滑动', (tester) async {
    await tester.pumpWidget(
      _metalHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (_) {},
        ),
      ),
    );

    expect(tester.getSize(find.byType(DownloadFilterBar)).width, 328);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    _expectCentered(tester);
    expect(_maxScrollExtent(tester), 0);
  });

  testWidgets('窄屏时保留最小宽度并可横向滑动', (tester) async {
    await tester.pumpWidget(
      _metalHost(
        DownloadFilterBar(
          selected: DownloadFilter.active,
          activeCount: 2,
          onChanged: (_) {},
        ),
        width: 240,
      ),
    );

    // 「进行中 2」的计数文案保留。
    expect(find.text('进行中 2'), findsOneWidget);
    expect(_maxScrollExtent(tester), greaterThan(0));

    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(
        of: find.byType(DownloadFilterBar),
        matching: find.byType(SingleChildScrollView),
      ),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    expect(
      tester.getSize(find.byType(AppSegmentedControl<DownloadFilter>)).width,
      greaterThanOrEqualTo(DownloadFilterBar.minCellWidth * 3),
    );

    // 滑到末尾仍能看到最后一个分段。
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('已完成'), findsOneWidget);
  });

  testWidgets('liquid glass 下仍是玻璃分段控件且居中', (tester) async {
    DownloadFilter? picked;
    await tester.pumpWidget(
      _glassHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (value) => picked = value,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GlassSegmentedControl), findsOneWidget);
    expect(
      tester.getSize(find.byType(GlassSegmentedControl)).width,
      328,
    );
    _expectCentered(tester);
    expect(_maxScrollExtent(tester), 0);

    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(picked, DownloadFilter.finished);
  });

  testWidgets('liquid glass 窄屏时保留最小宽度并可横向滑动', (tester) async {
    await tester.pumpWidget(
      _glassHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (_) {},
        ),
        width: 240,
      ),
    );
    await tester.pump();

    expect(
      tester.getSize(find.byType(GlassSegmentedControl)).width,
      greaterThanOrEqualTo(DownloadFilterBar.minCellWidth * 3),
    );
    expect(_maxScrollExtent(tester), greaterThan(0));

    // 窄屏外层靠 SingleChildScrollView 滑，控件本身仍是固定分段；透镜档位
    // 不因窄屏降级（scrollable 分支没有 glowColor/glowRadius 参数）。
    final control = tester.widget<GlassSegmentedControl>(
      find.byType(GlassSegmentedControl),
    );
    expect(control.quality, GlassQuality.premium);
    expect(
      control.indicatorSettings?.chromaticAberration,
      AppGlassTheme.dockIndicatorDispersion,
    );
    expect(control.indicatorPinchStrength, .4);
    expect(
      control.indicatorExpansion,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  });

  /// 选中透镜 = Dock 标定：premium 档才有折射/色散，外扩和 pinch 负责放大。
  testWidgets('玻璃筛选条按 Dock 标定透镜，按下才拉起玻璃层', (tester) async {
    await tester.pumpWidget(
      _glassHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    final control = tester.widget<GlassSegmentedControl>(
      find.byType(GlassSegmentedControl),
    );
    expect(control.quality, GlassQuality.premium);
    // Dock 解析出的 ios27 透镜（thickness 28 / RI 1.17 / paraxial）+ 显式色散；
    // 传 null 只有折射没有色散，等于用户说的「拖动块没有色散」。
    final lens = control.indicatorSettings;
    expect(lens, isNotNull);
    expect(lens!.chromaticAberration, AppGlassTheme.dockIndicatorDispersion);
    expect(lens.chromaticAberration, greaterThan(.10));
    expect(lens.thickness, 28);
    expect(lens.refractiveIndex, 1.17);
    expect(lens.lensModel, GlassLensModel.paraxial);
    expect(control.indicatorPinchStrength, .4);
    expect(
      control.indicatorExpansion,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(control.glowRadius, 1.5);
    expect(control.interactionBehavior, GlassInteractionBehavior.full);
    // 静止时没有常驻折射层，own layer 只在按下 / 拖动时由包内挂载。
    expect(find.byType(AdaptiveGlass), findsNothing);

    List<AnimatedGlassIndicator> lenses() => tester
        .widgetList<AnimatedGlassIndicator>(
          find.descendant(
            of: find.byType(GlassSegmentedControl),
            matching: find.byType(AnimatedGlassIndicator),
          ),
        )
        .toList();

    expect(lenses().first.thickness, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('全部')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final active = lenses().first;
    expect(active.thickness, greaterThan(.5));
    expect(active.quality, GlassQuality.premium);
    expect(active.pinchStrength, .4);
    expect(
      active.expansion,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(lenses().first.thickness, 0);
  });

  testWidgets('横向拖动越过相邻分段即切换分组', (tester) async {
    DownloadFilter? picked;
    await tester.pumpWidget(
      _glassHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (value) => picked = value,
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('全部')),
    );
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    // 拖动落在「已完成」上，外层横向 SingleChildScrollView 没有抢走手势。
    expect(picked, DownloadFilter.finished);
  });

  testWidgets('Reduce Motion 下关掉放大与光晕，镜层档位不变', (tester) async {
    await tester.pumpWidget(
      _glassHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (_) {},
        ),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    final control = tester.widget<GlassSegmentedControl>(
      find.byType(GlassSegmentedControl),
    );
    expect(control.quality, GlassQuality.premium);
    expect(control.indicatorPinchStrength, 0);
    expect(control.glowRadius, 0);
    expect(control.interactionBehavior, GlassInteractionBehavior.none);
    // Reduce Motion 只关运动；折射/色散是光学，由 Reduce Transparency 触发
    // 包内 respectSystemAccessibility 降级，这里不归零。
    expect(
      control.indicatorSettings?.chromaticAberration,
      AppGlassTheme.dockIndicatorDispersion,
    );
    expect(
      tester
          .widgetList<AnimatedGlassIndicator>(
            find.byType(AnimatedGlassIndicator),
          )
          .first
          .pinchStrength,
      0,
    );
  });

  testWidgets('Metal 分支不变：仍是 SegmentedButton，点选回传 value', (tester) async {
    DownloadFilter? picked;
    await tester.pumpWidget(
      _metalHost(
        DownloadFilterBar(
          selected: DownloadFilter.all,
          onChanged: (value) => picked = value,
        ),
      ),
    );

    expect(find.byType(GlassSegmentedControl), findsNothing);
    expect(find.byType(SegmentedButton<DownloadFilter>), findsOneWidget);
    await tester.tap(find.text('已完成'));
    await tester.pump();
    expect(picked, DownloadFilter.finished);
  });
}
