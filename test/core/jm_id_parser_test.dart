import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/utils/jm_id_parser.dart';

void main() {
  group('parseJmId', () {
    test('接受纯数字 / JM 前缀 / URL 形态', () {
      expect(parseJmId('350234'), '350234');
      expect(parseJmId('JM350234'), '350234');
      expect(parseJmId('jm 350234'), '350234');
      expect(parseJmId('https://18comic.vip/album/350234/'), '350234');
      expect(parseJmId('https://18comic.vip/photo/438516/'), '438516');
      expect(parseJmId('https://example.test/album/?id=350234'), '350234');
    });

    test('从中文前缀里提取数字并归一化前导零', () {
      expect(parseJmId('车号：350234'), '350234');
      expect(parseJmId('JM000123'), '123');
    });

    test('拒绝空 / 纯前缀 / 0 / 超长', () {
      expect(parseJmId(''), isNull);
      expect(parseJmId('JM'), isNull);
      expect(parseJmId('0'), isNull);
      expect(parseJmId('12345678901'), isNull);
    });
  });

  group('parseJmIds', () {
    test('按换行 / 逗号 / 全角逗号切分', () {
      expect(
        parseJmIds('350234\nJM350235, 350236，350237'),
        <String>['350234', '350235', '350236', '350237'],
      );
    });

    test('去重保序', () {
      expect(
        parseJmIds('JM350234 350234 https://18comic.vip/photo/438516/'),
        <String>['350234', '438516'],
      );
    });

    test('跳过无法解析的词条', () {
      expect(parseJmIds('350234\nJM\nabc'), <String>['350234']);
      expect(tokenizeJmIds('350234\nJM\nabc').length, 3);
    });
  });

  group('previewJmIds', () {
    test('统计有效与忽略数量', () {
      final preview = previewJmIds('350234 JM abc');
      expect(preview.ids.length, 1);
      expect(preview.ignored, 2);
      expect(preview.label.contains('1 个有效'), isTrue);
    });

    test('空输入给等待文案', () {
      expect(previewJmIds('   ').label, '等待输入');
    });
  });
}
