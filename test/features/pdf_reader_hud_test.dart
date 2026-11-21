import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/di/providers.dart';
import 'package:jm_comic/core/theme/interface_style_scope.dart';
import 'package:jm_comic/data/local/settings_store.dart';
import 'package:jm_comic/data/sources/pdf_reader_channel.dart';
import 'package:jm_comic/features/pdf/pdf_viewer_page.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class _PdfFixture implements PdfReader {
  @override
  Future<PdfDocumentInfo> open(String uri) async =>
      const PdfDocumentInfo(pageCount: 20);

  @override
  Future<Uint8List?> render(String uri, int index, int width) async => null;

  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('PDF Glass seek lands on release without a second animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [pdfReaderProvider.overrideWithValue(_PdfFixture())],
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
}
