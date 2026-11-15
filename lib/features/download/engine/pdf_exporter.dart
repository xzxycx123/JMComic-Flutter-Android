import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/config/app_config.dart';
import '../../../core/image/image_processor.dart';

/// PDF 导出（移植 `JmScript/export/PdfExporter.kt`）。
///
/// 语义保持一致：一页一图、页尺寸 = 位图尺寸（1px = 1pt）、长边上限 14400、白底。
abstract final class PdfExporter {
  /// 从已落盘的 PNG 页面生成 PDF 字节。
  static Future<Uint8List> exportFiles(
    List<File> pngFiles, {
    void Function(int done, int total)? onPage,
  }) async {
    if (pngFiles.isEmpty) {
      throw ArgumentError('没有可写入 PDF 的页面');
    }
    final document = pw.Document();
    var done = 0;
    for (final file in pngFiles) {
      final bytes = await file.readAsBytes();
      _addPage(document, bytes);
      done++;
      onPage?.call(done, pngFiles.length);
    }
    return document.save();
  }

  /// 直接从内存里的 PNG 页面生成（阅读器导出 / 单测用）。
  static Future<Uint8List> exportBytes(List<Uint8List> pngPages) async {
    if (pngPages.isEmpty) {
      throw ArgumentError('没有可写入 PDF 的页面');
    }
    final document = pw.Document();
    for (final bytes in pngPages) {
      _addPage(document, bytes);
    }
    return document.save();
  }

  static void _addPage(pw.Document document, Uint8List pngBytes) {
    final size = ImageProcessor.pngSizeSync(pngBytes);
    var width = size?.width ?? 1200;
    var height = size?.height ?? 1800;
    final longEdge = math.max(width, height);
    if (longEdge > AppConfig.maxPageEdge) {
      final scaled = ImageProcessor.pageSizeFor(width, height);
      width = scaled.width;
      height = scaled.height;
    }
    final pageFormat = PdfPageFormat(
      width.toDouble(),
      height.toDouble(),
      marginAll: 0,
    );
    final image = pw.MemoryImage(pngBytes);
    document.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(
            color: PdfColors.white,
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
