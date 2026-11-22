import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_colors.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_dialog.dart';
import 'package:jm_comic/core/ui/glass/app_sheet.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

Widget _host(AppInterfaceStyle style, WidgetBuilder builder) {
  return LiquidGlassWidgets.wrap(
    theme: AppGlassTheme.preset,
    brightnessResolver: Theme.maybeBrightnessOf,
    child: MaterialApp(
      builder: (context, child) =>
          InterfaceStyleScope(style: style, child: child!),
      home: Scaffold(body: Builder(builder: builder)),
    ),
  );
}

void main() {
  test('Metal 二级菜单（bottom sheet）用连续曲率的超椭圆圆角', () {
    for (final theme in <ThemeData>[AppTheme.light(), AppTheme.dark()]) {
      final shape = theme.bottomSheetTheme.shape;
      expect(
        shape,
        isA<RoundedSuperellipseBorder>(),
        reason: '二级菜单面板必须是 squircle（连续曲率），不是普通 RRect',
      );
      final borderRadius =
          (shape! as RoundedSuperellipseBorder).borderRadius as BorderRadius;
      expect(borderRadius.topLeft.x, AppColors.radiusPanel);
      expect(borderRadius.topRight.x, AppColors.radiusPanel);
      expect(borderRadius.bottomLeft, Radius.zero, reason: '只有顶边圆角');
    }
  });

  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style dialog returns a typed action exactly once',
        (tester) async {
      Future<int?>? result;
      var resolves = 0;
      await tester.pumpWidget(
        _host(
          style,
          (context) => TextButton(
            onPressed: () => result = AppDialog.show<int>(
              context: context,
              title: 'Confirm action',
              message: 'Verify the selected value',
              actions: [
                const AppDialogAction<int>(label: 'Cancel'),
                AppDialogAction<int>(
                    label: 'Confirm',
                    destructive: true,
                    resultBuilder: () => ++resolves,),
              ],
            ),
            child: const Text('Open dialog'),
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(
          find.byType(
              style == AppInterfaceStyle.metal ? AlertDialog : GlassDialog,),
          findsOneWidget,);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(await result, 1);
      expect(resolves, 1);
      expect(find.text('Open dialog'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$style sheet returns a typed value and keeps the caller theme',
        (tester) async {
      Future<int?>? result;
      await tester.pumpWidget(
        _host(
          style,
          (context) => Theme(
            data: ThemeData.dark(),
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => result = AppSheet.show<int>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(42),
                      child:
                          Text('Select ${Theme.of(context).brightness.name}'),
                    ),
                  ),
                ),
                child: const Text('Open sheet'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open sheet'));
      await tester.pumpAndSettle();
      if (style == AppInterfaceStyle.liquidGlass) {
        expect(find.byType(GlassModalSheet), findsOneWidget);
      }
      await tester.tap(find.text('Select dark'));
      await tester.pumpAndSettle();
      expect(await result, 42);
      expect(find.text('Open sheet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
