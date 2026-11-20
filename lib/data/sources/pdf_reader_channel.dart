
import 'package:flutter/services.dart';

/// 内置 PDF 阅读器的原生通道（Android `PdfRenderer`）。
///
/// 复用已下载的 `content://` PDF：不依赖任何第三方 PDF 插件，也不用外部阅读器。
class PdfDocumentInfo {
  const PdfDocumentInfo({required this.pageCount});

  final int pageCount;

  bool get isEmpty => pageCount <= 0;
}

abstract class PdfReader {
  /// 打开文档并返回页数。
  Future<PdfDocumentInfo> open(String uri);

  /// 渲染第 [index] 页（0 起）为 PNG 字节，宽度按 [width] 像素。
  Future<Uint8List?> render(String uri, int index, int width);

  /// 释放原生资源（切文档 / 退出阅读器时调用）。
  Future<void> close();
}

class PdfReaderChannel implements PdfReader {
  PdfReaderChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel('jm_comic/pdf_reader');

  final MethodChannel _channel;

  @override
  Future<PdfDocumentInfo> open(String uri) async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'open',
      <String, dynamic>{'uri': uri},
    );
    final pages = (result?['pages'] as num?)?.toInt() ?? 0;
    return PdfDocumentInfo(pageCount: pages);
  }

  @override
  Future<Uint8List?> render(String uri, int index, int width) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'render',
      <String, dynamic>{'uri': uri, 'index': index, 'width': width},
    );
    return bytes;
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<bool>('close');
  }
}
