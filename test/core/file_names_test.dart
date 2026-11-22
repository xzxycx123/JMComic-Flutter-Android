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

  group('章节 / 当页图片命名', () {
    test('章节号能解析时统一成「第N章」', () {
      expect(chapterFileLabel('第 1 话'), '第1章');
      expect(chapterFileLabel('第12話'), '第12章');
      expect(chapterFileLabel('ch. 3'), 'ch.3');
      expect(chapterFileLabel(''), '第1章');
    });

    test('JMComic-[jm编号]-第几章-第几页.png', () {
      expect(
        readerImageName(
          albumId: '350234',
          chapterTitle: '第 1 话',
          page: 7,
        ),
        'JMComic-350234-第1章-第7页.png',
      );
      expect(
        readerImageName(
          albumId: '350234',
          chapterTitle: '全一话',
          page: 1,
        ),
        'JMComic-350234-全一话-第1页.png',
      );
    });

    test('保存目录归一化：斜杠 / 空值', () {
      expect(normalizeSaveDir(''), defaultSaveImageDir);
      expect(normalizeSaveDir('  '), defaultSaveImageDir);
      expect(normalizeSaveDir('/Pictures/JMComicDownloader/'),
          'Pictures/JMComicDownloader',);
      expect(normalizeSaveDir(r'Pictures\JMComicDownloader'),
          'Pictures/JMComicDownloader',);
      expect(normalizeSaveDir('//a//b//'), 'a/b');
    });
  });
}
