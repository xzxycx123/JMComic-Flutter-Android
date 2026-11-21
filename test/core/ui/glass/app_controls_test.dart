import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/icons/app_icons.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_button.dart';
import 'package:jm_comic/core/ui/glass/app_chip.dart';
import 'package:jm_comic/core/ui/glass/app_segmented_control.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _host(Widget child, {AppInterfaceStyle? style, double textScale = 1}) =>
    LiquidGlassWidgets.wrap(
      theme: const GlassThemeData.ios27(),
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, navigator) {
          Widget tree = navigator!;
          if (style != null) {
            tree = InterfaceStyleScope(style: style, child: tree);
          }
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: tree,
          );
        },
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets(
      'Metal is the fallback; glass keeps button action and blocks repeated submissions',
      (tester) async {
    var clicks = 0;
    final cta = AppButton(
      label: '继续阅读 · 第 12 页',
      leadingIcon: const SvgIcon(AppIcons.play, size: 18),
      onPressed: () => clicks++,
    );
    await tester.pumpWidget(_host(cta));
    expect(find.byType(FilledButton), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byType(FilledButton))
            .style
            ?.shape
            ?.resolve({}),
        isA<LiquidRoundedSuperellipse>(),);
    await tester.tap(find.byType(FilledButton));
    expect(clicks, 1);

    await tester.pumpWidget(_host(cta, style: AppInterfaceStyle.liquidGlass));
    expect(find.byType(GlassButton), findsOneWidget);
    expect(
      tester.getSize(find.byType(GlassButton)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('继续阅读 · 第 12 页'));
    expect(clicks, 2);

    await tester.pumpWidget(
      _host(
        AppButton(label: '提交中', onPressed: () => clicks++, loading: true),
        style: AppInterfaceStyle.liquidGlass,
      ),
    );
    expect(find.byType(GlassProgressIndicator), findsOneWidget);
    expect(
      tester.widget<GlassButton>(find.byType(GlassButton)).enabled,
      isFalse,
    );
    await tester.tap(find.text('提交中'), warnIfMissed: false);
    expect(clicks, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'history chip selects and deletes separately; static label has no tap action',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    var deletes = 0;
    await tester.pumpWidget(
      _host(
        Wrap(
          children: [
            AppChip(
              label: const Text('搜索历史'),
              selected: true,
              onTap: () => taps++,
              onDeleted: () => deletes++,
            ),
            const AppChip(label: Text('静态标签')),
            AppChip(
              label: const Text('已禁用'),
              enabled: false,
              onTap: () => taps++,
            ),
          ],
        ),
        style: AppInterfaceStyle.liquidGlass,
      ),
    );
    expect(find.byType(GlassChip), findsNWidgets(3));
    expect(
      tester
          .getSemantics(find.text('静态标签'))
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isFalse,
    );
    await tester.tap(find.text('搜索历史'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('移除搜索历史'));
    await tester.tap(find.text('已禁用'), warnIfMissed: false);
    expect((taps, deletes), (1, 1));
    semantics.dispose();
  });

  testWidgets(
      'segmented lens maps to domain values and fits a narrow large-text layout',
      (tester) async {
    final changes = <int>[];
    Widget segments() => AppSegmentedControl<int>(
          segments: const [
            AppSegment(value: 11, label: Text('全部记录')),
            AppSegment(value: 24, label: Text('下载完成')),
            AppSegment(value: 39, label: Text('下载失败')),
          ],
          selected: 11,
          onChanged: changes.add,
        );
    await tester.pumpWidget(_host(SizedBox(width: 330, child: segments())));
    await tester.tap(find.text('下载完成'));
    expect(changes, [24]);

    await tester.pumpWidget(
      _host(
        SizedBox(width: 330, child: segments()),
        style: AppInterfaceStyle.liquidGlass,
      ),
    );
    await tester.tap(find.text('下载完成'));
    await tester.pump();
    expect(changes, [24, 24]);

    await tester.pumpWidget(
      _host(
        SizedBox(width: 180, child: segments()),
        style: AppInterfaceStyle.liquidGlass,
        textScale: 1.3,
      ),
    );
    expect(
      tester
          .widget<GlassSegmentedControl>(find.byType(GlassSegmentedControl))
          .isScrollable,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
