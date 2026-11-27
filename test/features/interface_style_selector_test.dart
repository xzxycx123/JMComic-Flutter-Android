import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/theme/interface_style_selector.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/test_env.dart';

Widget _app(
  Widget child, {
  required AppInterfaceStyle style,
  bool disableAnimations = false,
}) =>
    LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        theme: AppTheme.light(),
        builder: (context, navigator) => InterfaceStyleScope(
          style: style,
          child: MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: navigator!,
          ),
        ),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

Future<void> _pumpSelector(
  WidgetTester tester,
  ProviderContainer container, {
  required AppInterfaceStyle style,
  bool disableAnimations = false,
}) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _app(
        const InterfaceStyleSelector(),
        style: style,
        disableAnimations: disableAnimations,
      ),
    ),
  );
}

void main() {
  // 注意：设置写入是真实 Hive I/O，放在 testWidgets 的 fake-async 里会挂住
  // 后续测试的 Hive 调用，所以写库只在普通 test 中验证；widget 测试只读状态。
  setUpAll(initTestStores);

  testWidgets('材质切换滑杆走 Dock 透镜，静止不挂折射层', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSelector(
      tester,
      container,
      style: AppInterfaceStyle.liquidGlass,
    );
    await tester.pump();

    final control = tester.widget<GlassSegmentedControl>(
      find.byType(GlassSegmentedControl),
    );
    expect(control.quality, GlassQuality.premium);
    final lens = control.indicatorSettings;
    expect(lens, isNotNull);
    expect(lens!.chromaticAberration, AppGlassTheme.dockIndicatorDispersion);
    expect(lens.chromaticAberration, greaterThan(.10));
    expect(control.indicatorPinchStrength, .4);
    expect(
      control.indicatorExpansion,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    expect(control.glowRadius, 1.5);
    // 透镜只在按下 / 拖动时挂 own layer，静止时没有常驻折射层。
    expect(find.byType(AdaptiveGlass), findsNothing);
  });

  testWidgets('Reduce Motion 下材质切换滑杆不放大、不发光', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSelector(
      tester,
      container,
      style: AppInterfaceStyle.liquidGlass,
      disableAnimations: true,
    );
    await tester.pump();

    final control = tester.widget<GlassSegmentedControl>(
      find.byType(GlassSegmentedControl),
    );
    expect(control.quality, GlassQuality.premium);
    expect(control.indicatorPinchStrength, 0);
    expect(control.glowRadius, 0);
    expect(control.interactionBehavior, GlassInteractionBehavior.none);
    // Reduce Motion 只关运动：折射 / 色散属于光学，留给 Reduce Transparency
    // 由包内 respectSystemAccessibility 统一降级。
    expect(
      control.indicatorSettings?.chromaticAberration,
      AppGlassTheme.dockIndicatorDispersion,
    );
  });

  testWidgets('material 分支显示两个材质名称', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSelector(tester, container, style: AppInterfaceStyle.metal);

    expect(find.byType(GlassSegmentedControl), findsNothing);
    expect(find.byType(SegmentedButton<AppInterfaceStyle>), findsOneWidget);
    expect(find.text('material'), findsOneWidget);
    expect(find.text('Liquid Glass'), findsOneWidget);
  });

  test('材质设置写回 Hive，重启后仍读回 LiquidGlass', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(settingsProvider.notifier)
        .setInterfaceStyle(AppInterfaceStyle.liquidGlass);
    expect(
      Hive.box<dynamic>(HiveBoxes.settings).get('interfaceStyle'),
      AppInterfaceStyle.liquidGlass.code,
    );

    final restored = ProviderContainer();
    addTearDown(restored.dispose);
    expect(
      restored.read(interfaceStyleProvider),
      AppInterfaceStyle.liquidGlass,
    );
  });

  testWidgets('滑杆点选仍切回 material（与写库行为一致）', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await _pumpSelector(
      tester,
      container,
      style: AppInterfaceStyle.liquidGlass,
    );
    await tester.pump();
    expect(
      container.read(interfaceStyleProvider),
      AppInterfaceStyle.liquidGlass,
    );

    await tester.tap(find.text('material'));
    await tester.pump();
    expect(container.read(interfaceStyleProvider), AppInterfaceStyle.metal);
  });
}
