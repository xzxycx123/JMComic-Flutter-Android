import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/core/theme/theme_mode_selector.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// 只用内存存一份设置，避免 Hive 写盘定时器卡在 fake-async 里。
class _MemorySettings extends SettingsNotifier {
  AppSettings _value = const AppSettings();

  @override
  AppSettings build() => _value;

  @override
  Future<void> setThemeMode(AppThemeMode mode) async {
    _value = _value.copyWith(themeMode: mode);
    state = _value;
  }
}

Widget _host(AppInterfaceStyle style, Widget child, _MemorySettings settings) {
  return ProviderScope(
    overrides: <Override>[settingsProvider.overrideWith(() => settings)],
    child: LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        builder: (context, child) =>
            InterfaceStyleScope(style: style, child: child!),
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
}

void main() {
  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style：「主题模式」用气泡选项，点一下即时切换', (tester) async {
      final settings = _MemorySettings();
      await tester.pumpWidget(
        _host(style, const ThemeModeSelector(), settings),
      );
      await tester.pumpAndSettle();

      // 三个模式各一个气泡（浅色 / 深色 / 跟随系统）
      for (final mode in AppThemeMode.values) {
        expect(
          find.text(mode.label),
          findsWidgets,
          reason: '缺少「${mode.label}」气泡',
        );
      }
      // 默认浅色：标题右侧的胶囊 + 气泡各一份
      expect(find.text('浅色'), findsNWidgets(2));

      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();

      expect(settings.state.themeMode, AppThemeMode.dark);
      expect(find.text('深色'), findsNWidgets(2));
      expect(find.text('点气泡直接切换，立即生效'), findsOneWidget);
    });
  }

  testWidgets('不弹抽屉：主题选择器里没有打开 bottom sheet 的入口', (tester) async {
    final settings = _MemorySettings();
    await tester.pumpWidget(
      _host(AppInterfaceStyle.metal, const ThemeModeSelector(), settings),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();

    // 仍在同一页，没有弹出 modal 面板
    expect(find.byType(BottomSheet), findsNothing);
    expect(settings.state.themeMode, AppThemeMode.system);
  });
}
