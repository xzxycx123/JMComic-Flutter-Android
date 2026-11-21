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

Widget _glassHost(Widget child, {double width = 328}) =>
    LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => InterfaceStyleScope(
          style: AppInterfaceStyle.liquidGlass,
          child: child!,
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
  });
}
