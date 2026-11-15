import 'dart:math' as math;

import '../../data/sources/jm_crypto.dart';

/// 切片段数算法（与 `JmScript/image/ImageScrambler.kt` 一字节不差）。
///
/// ```
/// photoId < scrambleId            -> 0    （不切）
/// photoId < 268850                -> 10
/// 否则 modulus = photoId < 421926 ? 10 : 8
///      段数 = (md5hex("$photoId${filename去扩展名}").lastCodeUnit % modulus) * 2 + 2
/// ```
abstract final class ImageScrambler {
  static const int thresholdLegacy = 268850;
  static const int thresholdModern = 421926;

  /// [filename] 先 `substringBefore('?')` -> `substringAfterLast('/')` -> `substringBeforeLast('.')`。
  static String baseName(String filename) {
    final noQuery = filename.split('?').first;
    final noPath = noQuery.split('/').last;
    final dot = noPath.lastIndexOf('.');
    return dot <= 0 ? noPath : noPath.substring(0, dot);
  }

  static int segmentCount({
    required int scrambleId,
    required int photoId,
    required String filename,
  }) {
    if (photoId < scrambleId) return 0;
    if (photoId < thresholdLegacy) return 10;
    final modulus = photoId < thresholdModern ? 10 : 8;
    final hash = JmCrypto.md5Hex('$photoId${baseName(filename)}');
    // Kotlin 的 Char.code 即 UTF-16 code unit。
    return (hash.codeUnitAt(hash.length - 1) % modulus) * 2 + 2;
  }

  /// 单片高度分布（第 1 段吃掉余数），供还原算法与测试共用。
  static List<({int srcTop, int dstTop, int height})> sliceLayout({
    required int height,
    required int segments,
  }) {
    if (segments <= 0) {
      return <({int srcTop, int dstTop, int height})>[
        (srcTop: 0, dstTop: 0, height: height),
      ];
    }
    if (segments > height) {
      throw ArgumentError('图片切片参数异常：segments=$segments, height=$height');
    }
    final remainder = height % segments;
    final base = height ~/ segments;
    final layout = <({int srcTop, int dstTop, int height})>[];
    for (var i = 0; i < segments; i++) {
      var sliceHeight = base;
      final srcTop = height - (base * (i + 1)) - remainder;
      var dstTop = base * i;
      if (i == 0) {
        sliceHeight += remainder;
      } else {
        dstTop += remainder;
      }
      layout.add((srcTop: srcTop, dstTop: dstTop, height: sliceHeight));
    }
    return layout;
  }

  /// 便于测试断言：段数上限（用于裁剪异常输入）。
  static int clampSegments(int segments, int height) => math.min(segments, height);
}
