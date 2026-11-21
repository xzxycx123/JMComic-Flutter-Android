import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_slider.dart';
import 'package:jm_comic/core/ui/glass/app_surface.dart';
import 'package:jm_comic/core/ui/glass/app_switch.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _glassHost(Widget child) => LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        builder: (context, child) => InterfaceStyleScope(
          style: AppInterfaceStyle.liquidGlass,
          child: child!,
        ),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('list content and control groups do not refract', (tester) async {
    await tester.pumpWidget(
      _glassHost(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSurface(child: Text('Content')),
            AppSurface(
              kind: AppSurfaceKind.controlGroup,
              child: AppSwitch(value: false, onChanged: null),
            ),
          ],
        ),
      ),
    );
    final surfaces =
        tester.widgetList<GlassContainer>(find.byType(GlassContainer));
    expect(surfaces, hasLength(2));
    expect(surfaces.every((surface) => !surface.useOwnLayer), isTrue);
    expect(find.byType(AdaptiveGlass), findsNothing);
    expect(find.byType(GlassSwitch), findsOneWidget);
    final switchContext = tester.element(find.byType(GlassSwitch));
    expect(InheritedGlassSurfaceStyle.maybeOf(switchContext),
        GlassSurfaceStyle.solid,);
  });

  testWidgets('slider taps seek once and drags commit only on release',
      (tester) async {
    final previews = <double>[];
    final commits = <double>[];
    await tester.pumpWidget(
      _glassHost(
        SizedBox(
          width: 230,
          child: AppSlider(
            value: 2,
            min: 0,
            max: 10,
            divisions: 10,
            onChanged: previews.add,
            onChangeEnd: commits.add,
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(GlassSlider));
    await tester.tapAt(Offset(bounds.right - 15, bounds.center.dy));
    expect(previews, [10]);
    expect(commits, [10]);
    previews.clear();
    commits.clear();

    final drag =
        await tester.startGesture(Offset(bounds.left + 55, bounds.center.dy));
    await drag.moveBy(const Offset(30, 0));
    await drag.moveBy(const Offset(80, 0));
    expect(previews, isNotEmpty);
    expect(commits, isEmpty);
    await drag.up();
    expect(commits, [previews.last]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
