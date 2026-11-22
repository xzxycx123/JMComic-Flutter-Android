import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/app_version.dart';
import 'package:jm_comic/data/models/release_info.dart';
import 'package:jm_comic/data/models/release_notes.dart';
import 'package:jm_comic/data/repositories/update_repository.dart';
import 'package:jm_comic/features/update/update_gate.dart';
import 'package:jm_comic/features/update/update_providers.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:mocktail/mocktail.dart';

class _MockUpdateRepository extends Mock implements UpdateRepository {}

class _MemorySettings extends SettingsNotifier {
  _MemorySettings([AppSettings? initial]) : _value = initial ?? const AppSettings();

  AppSettings _value;

  @override
  AppSettings build() => _value;

  @override
  Future<void> setSkippedReleaseTag(String tag) async {
    _value = _value.copyWith(skippedReleaseTag: tag);
    state = _value;
  }
}

ReleaseInfo _release() => ReleaseInfo(
      tag: 'v0.4.4',
      version: AppVersion.tryParse('0.4.4')!,
      title: 'JMComic v0.4.4',
      notes: ReleaseNotes.markdown('# JMComic v0.4.4\n\n- 自动更新'),
      htmlUrl:
          'https://github.com/xzxycx123/JMComic-Flutter-Android/releases/tag/v0.4.4',
      apk: const ReleaseAsset(
        name: 'JMComic-0.4.4-release.apk',
        downloadUrl: 'https://example.com/a.apk',
      ),
    );

Widget _host({
  required Widget child,
  required ProviderContainer container,
  AppInterfaceStyle style = AppInterfaceStyle.metal,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: LiquidGlassWidgets.wrap(
      theme: AppGlassTheme.preset,
      brightnessResolver: Theme.maybeBrightnessOf,
      child: MaterialApp(
        builder: (context, child) =>
            InterfaceStyleScope(style: style, child: child!),
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(AppVersion.unknown);
  });

  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style：启动即检查，有新版弹「检测到新版本」', (tester) async {
      final repo = _MockUpdateRepository();
      when(() => repo.installedVersion).thenReturn(AppVersion.tryParse('0.4.3')!);
      when(repo.resolveInstalledVersion)
          .thenAnswer((_) async => AppVersion.tryParse('0.4.3')!);
      when(() => repo.findNewerThan(any())).thenAnswer((_) async => _release());

      final container = ProviderContainer(
        overrides: <Override>[
          updateRepositoryProvider.overrideWithValue(repo),
          settingsProvider.overrideWith(_MemorySettings.new),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        _host(
          style: style,
          container: container,
          child: const UpdateGate(child: Text('首页')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('检测到新版本'), findsOneWidget);
      expect(find.text('首页'), findsOneWidget, reason: '弹窗是盖在页面上的');

      // 跳过此版本：记住 tag，下次启动不再弹
      await tester.tap(find.text('跳过此版本'));
      await tester.pumpAndSettle();
      expect(find.text('检测到新版本'), findsNothing);
      expect(container.read(settingsProvider).skippedReleaseTag, 'v0.4.4');

      // 「已跳过」提示自带 3s 计时器，等它跑完再收尾，别留 pending timer。
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('已跳过该 tag 时启动不再弹窗', (tester) async {
    final repo = _MockUpdateRepository();
    when(() => repo.installedVersion).thenReturn(AppVersion.tryParse('0.4.3')!);
    when(repo.resolveInstalledVersion)
        .thenAnswer((_) async => AppVersion.tryParse('0.4.3')!);
    when(() => repo.findNewerThan(any())).thenAnswer((_) async => _release());

    final container = ProviderContainer(
      overrides: <Override>[
        updateRepositoryProvider.overrideWithValue(repo),
        settingsProvider.overrideWith(
          () => _MemorySettings(const AppSettings(skippedReleaseTag: 'v0.4.4')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container: container,
        child: const UpdateGate(child: Text('首页')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('检测到新版本'), findsNothing);
    expect(container.read(updateCheckProvider).release?.tag, 'v0.4.4');
    expect(container.read(updateCheckProvider).phase, UpdatePhase.available);
  });

  testWidgets('关掉「自动检查更新」后启动不查网络', (tester) async {
    final repo = _MockUpdateRepository();
    when(() => repo.installedVersion).thenReturn(AppVersion.tryParse('0.4.3')!);
    when(repo.resolveInstalledVersion)
        .thenAnswer((_) async => AppVersion.tryParse('0.4.3')!);
    when(() => repo.findNewerThan(any())).thenAnswer((_) async => _release());

    final container = ProviderContainer(
      overrides: <Override>[
        updateRepositoryProvider.overrideWithValue(repo),
        settingsProvider.overrideWith(
          () => _MemorySettings(const AppSettings(autoUpdateCheck: false)),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container: container,
        child: const UpdateGate(child: Text('首页')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('检测到新版本'), findsNothing);
    verifyNever(() => repo.findNewerThan(any()));
  });

  testWidgets('已是最新时启动只更新状态，不弹窗', (tester) async {
    final repo = _MockUpdateRepository();
    when(() => repo.installedVersion).thenReturn(AppVersion.tryParse('0.4.4')!);
    when(repo.resolveInstalledVersion)
        .thenAnswer((_) async => AppVersion.tryParse('0.4.4')!);
    when(() => repo.findNewerThan(any())).thenAnswer((_) async => null);

    final container = ProviderContainer(
      overrides: <Override>[
        updateRepositoryProvider.overrideWithValue(repo),
        settingsProvider.overrideWith(_MemorySettings.new),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      _host(
        container: container,
        child: const UpdateGate(child: Text('首页')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('检测到新版本'), findsNothing);
    expect(container.read(updateCheckProvider).phase, UpdatePhase.upToDate);
    expect(container.read(updateCheckProvider).summary, '已是最新');
  });
}
