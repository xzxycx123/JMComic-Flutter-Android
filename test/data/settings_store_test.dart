import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:jm_comic/data/local/hive_init.dart';
import 'package:jm_comic/data/local/settings_store.dart';

import '../helpers/test_env.dart';

void main() {
  setUpAll(() async {
    await initTestStores();
  });

  setUp(() async {
    await clearTestBoxes();
  });

  test('界面材质默认 Metal，未知持久化值也回退 Metal', () async {
    final box = Hive.box<dynamic>(HiveBoxes.settings);
    final store = SettingsStore(box);

    expect(store.read().interfaceStyle, AppInterfaceStyle.metal);

    await box.put('interfaceStyle', 'unknown-style');
    expect(store.read().interfaceStyle, AppInterfaceStyle.metal);
  });

  test('LiquidGlass 选择即时生效并持久化，且不影响明暗模式', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(settingsProvider.notifier)
        .setInterfaceStyle(AppInterfaceStyle.liquidGlass);

    expect(
      container.read(interfaceStyleProvider),
      AppInterfaceStyle.liquidGlass,
    );
    expect(container.read(settingsProvider).themeMode, AppThemeMode.light);

    final restored = SettingsStore(
      Hive.box<dynamic>(HiveBoxes.settings),
    ).read();
    expect(restored.interfaceStyle, AppInterfaceStyle.liquidGlass);
    expect(restored.themeMode, AppThemeMode.light);
  });
}
