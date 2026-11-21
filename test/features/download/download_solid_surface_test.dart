import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/app_colors.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/app_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/ui/glass/app_button.dart';
import 'package:jm_comic/core/ui/glass/app_surface.dart';
import 'package:jm_comic/core/ui/glass/app_text_field.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/download_record.dart';
import 'package:jm_comic/features/download/widgets/download_input.dart';
import 'package:jm_comic/features/download/widgets/task_card.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../helpers/fixtures.dart';

Widget _metalHost(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

/// 找出「实色卡片」：Container + BoxDecoration + surfaceContainer 底色。
Finder _solidCard(Color color) => find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).color == color,
    );

void main() {
  testWidgets('下载输入区是 solid 表面，主按钮药丸形', (tester) async {
    final controller = TextEditingController(text: '350234');
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      _metalHost(
        DownloadInput(controller: controller, onSubmit: () {}),
      ),
    );

    // 不再有 AppSurface（玻璃容器）包住输入卡。
    expect(find.byType(AppSurface), findsNothing);
    final scheme =
        Theme.of(tester.element(find.byType(DownloadInput))).colorScheme;
    expect(_solidCard(scheme.surfaceContainer), findsOneWidget);

    final submit =
        tester.widget<AppButton>(find.widgetWithText(AppButton, '加入队列'));
    expect(submit.cornerRadius, AppColors.radiusPill);
    expect(submit.solid, isTrue);
    expect(
      tester
          .widget<AppButton>(find.widgetWithText(AppButton, '粘贴'))
          .cornerRadius,
      AppColors.radiusPill,
    );
    expect(find.byType(AppTextField), findsOneWidget);
  });

  testWidgets('liquid glass 模式下输入区仍走 solid（无折射层嵌套）', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
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
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: DownloadInput(controller: controller, onSubmit: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppSurface), findsNothing);
    // 输入框 / 主按钮都压成 GlassSurfaceStyle.solid，不生成折射层。
    expect(
      find.descendant(
        of: find.byType(DownloadInput),
        matching: find.byType(AdaptiveGlass),
      ),
      findsNothing,
    );
    final scopeStyle = InheritedGlassSurfaceStyle.maybeOf(
      tester.element(find.byType(AppTextField)),
    );
    expect(scopeStyle, GlassSurfaceStyle.solid);
  });

  testWidgets('任务卡为 solid 卡片，不再包玻璃表面', (tester) async {
    const record = DownloadRecord(
      workId: '1',
      albumId: '100',
      title: '測試漫畫',
      state: DownloadState.running,
      status: '下载中',
      done: 3,
      total: 10,
      percent: 30,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          jmApiProvider.overrideWithValue(FakeJmApi()),
          jmBootstrapProvider
              .overrideWith((ref) => Completer<FakeJmApi>().future),
        ],
        child: _metalHost(const TaskCard(record: record)),
      ),
    );

    expect(find.byType(AppSurface), findsNothing);
    final scheme = Theme.of(tester.element(find.byType(TaskCard))).colorScheme;
    expect(_solidCard(scheme.surfaceContainer), findsOneWidget);
    expect(find.text('測試漫畫'), findsOneWidget);
    expect(find.text('下载中 · 3/10 页'), findsOneWidget);
  });
}
