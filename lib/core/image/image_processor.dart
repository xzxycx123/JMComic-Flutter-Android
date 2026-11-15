import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config/app_config.dart';
import 'image_scrambler.dart';

/// 一次还原请求（可跨 isolate 传递）。
@immutable
class RestoreRequest {
  const RestoreRequest({
    required this.raw,
    required this.scrambleId,
    required this.photoId,
    required this.filename,
  });

  final Uint8List raw;
  final int scrambleId;
  final int photoId;
  final String filename;
}

/// 切片还原 + PNG 重编码（移植 `JmScript/image/ImageProcessor.kt`）。
///
/// 解码、切块、重编码全部在 [compute] 的 isolate 里跑，避免大图卡住 UI。
abstract final class ImageProcessor {
  /// 解码失败 / 尺寸异常返回 null，由调用方转成可读异常。
  static Uint8List? restoreSync(RestoreRequest request) {
    final decoded = img.decodeImage(request.raw);
    if (decoded == null) return null;

    final segments = ImageScrambler.segmentCount(
      scrambleId: request.scrambleId,
      photoId: request.photoId,
      filename: request.filename,
    );
    if (segments <= 0) {
      return Uint8List.fromList(img.encodePng(decoded));
    }
    if (segments > decoded.height) return null;

    final layout = ImageScrambler.sliceLayout(
      height: decoded.height,
      segments: segments,
    );
    final output = img.Image(width: decoded.width, height: decoded.height);
    for (final slice in layout) {
      final piece = img.copyCrop(
        decoded,
        x: 0,
        y: slice.srcTop,
        width: decoded.width,
        height: slice.height,
      );
      img.compositeImage(output, piece, dstY: slice.dstTop);
    }
    return Uint8List.fromList(img.encodePng(output));
  }

  /// isolate 包装：失败返回 null。
  static Future<Uint8List?> restore(RestoreRequest request) =>
      compute(_restoreEntry, request);

  /// 重新编码 PNG（PDF 只吃 PNG/JPEG；AVIF 等格式先在 Dart 侧转 PNG）。
  static Uint8List? transcodeToPngSync(Uint8List raw) {
    final decoded = img.decodeImage(raw);
    if (decoded == null) return null;
    return Uint8List.fromList(img.encodePng(decoded));
  }

  /// 只读 PNG 头里的宽高（不整图解码，避免 PDF 导出时二次解压大图）。
  static ({int width, int height})? pngSizeFromHeader(Uint8List bytes) {
    if (bytes.length < 24) return null;
    const signature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
    for (var index = 0; index < signature.length; index++) {
      if (bytes[index] != signature[index]) return null;
    }
    // IHDR：8 字节签名 + 4 字节长度 + 4 字节类型 + 宽(4) + 高(4)，大端序。
    int readUint32(int offset) =>
        (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
    final width = readUint32(16);
    final height = readUint32(20);
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }

  /// 读取 PNG 尺寸（PDF 页尺寸 = 位图尺寸），解不出来返回 null。
  static ({int width, int height})? pngSizeSync(Uint8List raw) {
    final fromHeader = pngSizeFromHeader(raw);
    if (fromHeader != null) return fromHeader;
    final decoded = img.decodePng(raw);
    if (decoded == null) return null;
    return (width: decoded.width, height: decoded.height);
  }

  /// 页面尺寸换算：长边上限 14400，等比缩放。
  static ({int width, int height}) pageSizeFor(int width, int height) {
    final longEdge = width > height ? width : height;
    if (longEdge <= AppConfig.maxPageEdge) {
      return (width: width, height: height);
    }
    final scale = AppConfig.maxPageEdge / longEdge;
    return (
      width: (width * scale).ceil().clamp(1, AppConfig.maxPageEdge.toInt()).toInt(),
      height: (height * scale).ceil().clamp(1, AppConfig.maxPageEdge.toInt()).toInt(),
    );
  }
}

Future<Uint8List?> _restoreEntry(RestoreRequest request) async {
  try {
    return ImageProcessor.restoreSync(request);
  } catch (_) {
    return null;
  }
}
