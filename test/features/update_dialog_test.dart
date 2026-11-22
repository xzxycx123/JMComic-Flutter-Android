import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/theme/app_glass_theme.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/models/app_version.dart';
import 'package:jm_comic/data/models/release_info.dart';
import 'package:jm_comic/data/models/release_notes.dart';
import 'package:jm_comic/features/update/update_dialog.dart';
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

ReleaseInfo _release() => ReleaseInfo(
      tag: 'v0.4.4',
      version: AppVersion.tryParse('0.4.4')!,
      title: 'JMComic v0.4.4',
      notes: ReleaseNotes.markdown(
        '# JMComic v0.4.4\n\n'
        '## 功能添加\n\n'
        '- 自动更新\n'
        '- 结束页保存 PDF\n',
      ),
      htmlUrl: 'https://github.com/xzxycx123/JMComic-Flutter-Android/releases/tag/v0.4.4',
      apk: const ReleaseAsset(
        name: 'JMComic-0.4.4-release.apk',
        downloadUrl: 'https://example.com/a.apk',
        sizeBytes: 70000000,
      ),
      publishedAt: DateTime.utc(2026, 11, 23, 9),
    );

void main() {
  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style：弹窗显示标题 / release 说明 / 三个选项', (tester) async {
      UpdateChoice? choice;
      await tester.pumpWidget(
        _host(
          style,
          (context) => TextButton(
            onPressed: () async {
              choice = await showUpdateDialog(
                context: context,
                release: _release(),
                current: AppVersion.tryParse('0.4.3')!,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('检测到新版本'), findsOneWidget);
      expect(find.text('JMComic v0.4.4'), findsWidgets);
      expect(find.text('v0.4.4'), findsWidgets);
      expect(find.text('当前 v0.4.3'), findsOneWidget);
      // release 页 readme 的正文
      expect(find.text('功能添加'), findsOneWidget);
      expect(find.text('自动更新'), findsOneWidget);

      // 三个出口：安装 / 取消 / 跳过此版本
      expect(find.text('安装'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      await tester.tap(find.text('跳过此版本'));
      await tester.pumpAndSettle();
      expect(choice, UpdateChoice.skip);
    });

    testWidgets('$style：点「取消」只是关掉弹窗（下次还会弹）', (tester) async {
      UpdateChoice? choice;
      await tester.pumpWidget(
        _host(
          style,
          (context) => TextButton(
            onPressed: () async {
              choice = await showUpdateDialog(
                context: context,
                release: _release(),
                current: AppVersion.tryParse('0.4.3')!,
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(choice, UpdateChoice.later);
      expect(find.text('检测到新版本'), findsNothing);
    });
  }
}
