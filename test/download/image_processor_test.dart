import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jm_comic/core/image/image_processor.dart';
import 'package:jm_comic/core/image/image_scrambler.dart';

import '../helpers/fixtures.dart';

void main() {
  test('切片还原后像素与原件一致', () {
    final original = syntheticPng(width: 40, height: 90, seed: 3);
    final segments = ImageScrambler.segmentCount(
      scrambleId: 220980,
      photoId: 350234,
      filename: '00001.webp',
    );
    expect(segments, 2);

    final scrambled = scramblePng(original, segments: segments);
    final restored = ImageProcessor.restoreSync(
      RestoreRequest(
        raw: scrambled,
        scrambleId: 220980,
        photoId: 350234,
        filename: '00001.webp',
      ),
    );

    expect(restored, isNotNull);
    final source = img.decodePng(original)!;
    final target = img.decodePng(restored!)!;
    expect(target.width, source.width);
    expect(target.height, source.height);
    for (final point in <(int, int)>[(0, 0), (13, 7), (39, 89), (20, 45)]) {
      final a = source.getPixel(point.$1, point.$2);
      final b = target.getPixel(point.$1, point.$2);
      expect(b.r.toInt(), a.r.toInt(), reason: 'R @$point');
      expect(b.g.toInt(), a.g.toInt(), reason: 'G @$point');
      expect(b.b.toInt(), a.b.toInt(), reason: 'B @$point');
    }
  });

  test('segments=0 时只重编码成 PNG', () {
    final original = syntheticPng(width: 24, height: 36, seed: 9);
    final restored = ImageProcessor.restoreSync(
      RestoreRequest(
        raw: original,
        scrambleId: 220980,
        photoId: 100,
        filename: '00001.webp',
      ),
    );
    expect(restored, isNotNull);
    final decoded = img.decodePng(restored!)!;
    expect(decoded.width, 24);
    expect(decoded.height, 36);
  });

  test('坏字节返回 null（由调用方转可读异常）', () {
    final restored = ImageProcessor.restoreSync(
      RestoreRequest(
        raw: Uint8List.fromList(<int>[1, 2, 3, 4]),
        scrambleId: 220980,
        photoId: 350234,
        filename: '00001.webp',
      ),
    );
    expect(restored, isNull);
  });

  test('pageSizeFor 长边不超过 14400', () {
    final size = ImageProcessor.pageSizeFor(30000, 15000);
    expect(math.max(size.width, size.height) <= 14400, isTrue);
    expect(size.width > size.height, isTrue);
  });

  test('pngSizeSync 能读回尺寸', () {
    final bytes = syntheticPng(width: 33, height: 44);
    final size = ImageProcessor.pngSizeSync(bytes);
    expect(size?.width, 33);
    expect(size?.height, 44);
  });
}
