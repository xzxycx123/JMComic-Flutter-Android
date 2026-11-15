import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/utils/file_names.dart';

void main() {
  group('pdfName', () {
    test('非法字符替换 + 空白折叠', () {
      expect(pdfName('123', '  Test:\n/Comic  '), 'JM123 - Test___Comic.pdf');
    });

    test('纯标点标题回落 comic', () {
      expect(pdfName('123', '...'), 'JM123 - comic.pdf');
    });

    test('按码点截断不劈开 emoji', () {
      final result = pdfName('123', '😀' * 100);
      final title = result.replaceFirst('JM123 - ', '').replaceFirst('.pdf', '');
      expect(title.runes.length, 80);
      expect(result.endsWith('.pdf'), isTrue);
    });
  });

  group('nextAvailablePdfName', () {
    test('同名递增到 (2)/(3)', () {
      expect(nextAvailablePdfName('a.pdf', <String>[]), 'a.pdf');
      expect(nextAvailablePdfName('a.pdf', <String>['a.pdf']), 'a (2).pdf');
      expect(
        nextAvailablePdfName('a.pdf', <String>['a.pdf', 'a (2).pdf']),
        'a (3).pdf',
      );
    });
  });
}
