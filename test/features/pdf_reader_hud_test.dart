import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/progress_store.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/sources/pdf_reader_channel.dart';
import 'package:jm_comic/features/pdf/pdf_viewer_page.dart';
import 'package:jm_comic/features/reader/reader_image_saver.dart';
import 'package:jm_comic/features/reader/reader_providers.dart';
import 'package:jm_comic/features/reader/widgets/reader_tap_zones.dart';
import 'package:jm_comic/features/reader/widgets/scroll_reader_view.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../helpers/fixtures.dart';

class _PdfFixture implements PdfReader {
  final Uint8List bytes = syntheticPng();

  @override
  Future<PdfDocumentInfo> open(String uri) async =>
      const PdfDocumentInfo(pageCount: 20);

  @override
  Future<Uint8List?> render(String uri, int index, int width) async => bytes;

  @override
  Future<void> close() async {}
}

class _PdfProgress extends Fake implements ProgressStore {
  final pages = <String, int>{};

  @override
  int? readPdfPage(String uri) => pages[uri];

  @override
  Future<void> writePdfPage(String uri, int page) async {
    pages[uri] = page;
  }
}

class _ReaderSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> setPageTurnAnimation(bool enabled) async {
    state = state.copyWith(pageTurnAnimation: enabled);
  }

  @override
  Future<void> setDefaultReaderMode(String mode) async {
    state = state.copyWith(defaultReaderMode: mode);
  }
}

void main() {
  testWidgets('PDF Glass seek lands on release without a second animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfReaderProvider.overrideWithValue(_PdfFixture()),
          progressStoreProvider.overrideWithValue(_PdfProgress()),
          settingsProvider.overrideWith(_ReaderSettings.new),
        ],
        child: LiquidGlassWidgets.wrap(
          child: const MaterialApp(
            home: InterfaceStyleScope(
              style: AppInterfaceStyle.liquidGlass,
              child: PdfViewerPage(args: PdfViewerArgs(uri: 'fixture')),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final controller =
        tester.widget<PageView>(find.byType(PageView)).controller!;
    final track = tester.getRect(find.byType(GlassSlider));
    final gesture = await tester.startGesture(track.center);
    await gesture.moveBy(Offset(track.width * .25, 0));
    await gesture.moveBy(Offset(track.width * .5, 0));
    await tester.pump();
    expect(controller.page, 0);
    expect(find.text('已读 20/20'), findsOneWidget);
    await gesture.up();
    expect(controller.page, 19);
    await tester.pump(const Duration(milliseconds: 125));
    expect(controller.page, 19);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final style in AppInterfaceStyle.values) {
    testWidgets('$style PDF 使用共享菜单、保存当前页并恢复进度', (tester) async {
      final progress = _PdfProgress();
      final settings = _ReaderSettings();
      final saver = MemoryReaderImageSaver();
      final fixture = _PdfFixture();
      final router = GoRouter(
        initialLocation: '/download',
        routes: [
          GoRoute(
            path: '/download',
            builder: (context, _) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push('/pdf'),
                  child: const Text('打开 PDF'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/pdf',
            builder: (context, _) => const PdfViewerPage(
              args: PdfViewerArgs(uri: 'fixture', title: '测试.pdf'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pdfReaderProvider.overrideWithValue(fixture),
            progressStoreProvider.overrideWithValue(progress),
            readerImageSaverProvider.overrideWithValue(saver),
            settingsProvider.overrideWith(() => settings),
          ],
          child: LiquidGlassWidgets.wrap(
            theme: const GlassThemeData.ios27(),
            child: MaterialApp.router(
              routerConfig: router,
              builder: (context, child) =>
                  InterfaceStyleScope(style: style, child: child!),
            ),
          ),
        ),
      );

      Future<void> openMore() async {
        await tester.tap(
          style == AppInterfaceStyle.liquidGlass
              ? find.byType(GlassPullDownButton)
              : find.byTooltip('更多'),
        );
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('打开 PDF'));
      await tester.pumpAndSettle();

      await openMore();
      expect(find.text('翻页方式'), findsOneWidget);
      expect(find.text('翻页动画'), findsOneWidget);
      expect(find.text('选择节点'), findsNothing);
      await tester.tap(find.text('翻页动画'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PdfViewerPage)),
        listen: false,
      );
      expect(container.read(settingsProvider).pageTurnAnimation, isFalse);
      await tester.tap(find.text('下载当页图片'));
      await tester.pumpAndSettle();
      expect(saver.files['测试-第1页.png'], fixture.bytes);
      expect(find.textContaining('已保存'), findsOneWidget);

      final reader = tester.getRect(find.byType(ReaderTapZones));
      await tester.tapAt(Offset(reader.right - 20, reader.center.dy));
      await tester.pumpAndSettle();
      expect(find.text('已读 2/20'), findsOneWidget);
      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      expect(find.text('打开 PDF'), findsOneWidget);
      expect(progress.readPdfPage('fixture'), 2);

      await tester.tap(find.text('打开 PDF'));
      await tester.pumpAndSettle();
      expect(find.text('已读 2/20'), findsOneWidget);
      await openMore();
      await tester.tap(find.text('翻页方式'));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollReaderView), findsOneWidget);
      expect(find.text('已读 2/20'), findsOneWidget);
      expect(container.read(settingsProvider).defaultReaderMode, 'vertical');

      unawaited(tester.binding.handlePopRoute());
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开 PDF'));
      await tester.pumpAndSettle();
      expect(find.byType(ScrollReaderView), findsOneWidget);
      expect(find.text('已读 2/20'), findsOneWidget);
      final scroll = tester.widget<ScrollReaderView>(
        find.byType(ScrollReaderView),
      );
      expect(scroll.controller.offset, scroll.itemExtent);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
