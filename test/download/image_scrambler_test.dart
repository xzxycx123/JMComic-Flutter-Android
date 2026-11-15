import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/image/image_scrambler.dart';

void main() {
  group('segmentCount（PLAN §10.1 向量）', () {
    test('不切 / 旧阈值 10 段', () {
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 100, filename: '00001.webp'), 0);
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 220980, filename: '00001.webp'), 10);
    });

    test('文件名哈希决定段数', () {
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 268850, filename: '00001.webp'), 6);
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 268850, filename: '00002.webp'), 4);
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 421926, filename: '00001.webp'), 14);
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 421926, filename: '00002.webp'), 12);
      expect(
        ImageScrambler.segmentCount(scrambleId: 220980, photoId: 421926, filename: '/photos/00001.webp?v=1'),
        14,
      );
      expect(ImageScrambler.segmentCount(scrambleId: 220980, photoId: 350234, filename: '00001.webp'), 2);
    });
  });

  group('sliceLayout', () {
    test('第一段吃掉余数，src 倒序、dst 顺序', () {
      final layout = ImageScrambler.sliceLayout(height: 100, segments: 3);
      expect(layout.length, 3);
      expect(layout[0].srcTop, 100 - 33 - 1);
      expect(layout[0].height, 34);
      expect(layout[0].dstTop, 0);
      expect(layout[2].srcTop, 0);
      expect(layout[2].dstTop, 34 + 33);
    });

    test('段数大于高度时抛错', () {
      expect(() => ImageScrambler.sliceLayout(height: 2, segments: 4), throwsArgumentError);
    });
  });

  group('baseName', () {
    test('去查询串 / 路径 / 扩展名', () {
      expect(ImageScrambler.baseName('/media/photos/00001.webp?v=1'), '00001');
      expect(ImageScrambler.baseName('00002.webp'), '00002');
    });
  });
}
