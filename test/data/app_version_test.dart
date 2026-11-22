import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/app_version.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('兼容 v 前缀 / 无前缀 / 四段版本', () {
      expect(AppVersion.tryParse('v0.4.3')?.segments, <int>[0, 4, 3]);
      expect(AppVersion.tryParse('0.4.3')?.segments, <int>[0, 4, 3]);
      expect(AppVersion.tryParse('0.3.3.1')?.segments, <int>[0, 3, 3, 1]);
      expect(AppVersion.tryParse(' release-0.4.0 ')?.segments, <int>[0, 4]);
      expect(AppVersion.tryParse('JMComic-v0.4.2')?.segments, <int>[0, 4, 2]);
    });

    test('去掉尾部 0 段，构版本号不参与比较', () {
      expect(AppVersion.tryParse('1.2.0')?.segments, <int>[1, 2]);
      expect(AppVersion.tryParse('0.4.3+11')?.segments, <int>[0, 4, 3]);
      expect(AppVersion.tryParse('0.4.3+11')?.prerelease, isFalse);
    });

    test('预发布后缀标记 prerelease', () {
      expect(AppVersion.tryParse('v0.5.0-beta.1')?.prerelease, isTrue);
      expect(AppVersion.tryParse('v0.5.0-beta.1')?.segments, <int>[0, 5]);
    });

    test('解析不出来的 tag 返回 null', () {
      expect(AppVersion.tryParse(null), isNull);
      expect(AppVersion.tryParse('  '), isNull);
      expect(AppVersion.tryParse('nightly'), isNull);
    });
  });

  group('版本比较', () {
    final current = AppVersion.tryParse('0.4.3')!;

    test('更高的版本号才算更新', () {
      expect(AppVersion.tryParse('v0.4.4')!.isNewerThan(current), isTrue);
      expect(AppVersion.tryParse('v0.5.0')!.isNewerThan(current), isTrue);
      expect(AppVersion.tryParse('v1.0.0')!.isNewerThan(current), isTrue);
      expect(AppVersion.tryParse('0.3.3.1')!.isNewerThan(current), isFalse);
      expect(AppVersion.tryParse('v0.4.3')!.isNewerThan(current), isFalse);
      expect(AppVersion.tryParse('v0.4.2')!.isNewerThan(current), isFalse);
    });

    test('段数不同按 0 补齐', () {
      final patch = AppVersion.tryParse('0.3.3.1')!;
      expect(patch.isNewerThan(AppVersion.tryParse('0.3.3')!), isTrue);
      expect(AppVersion.tryParse('0.4')!.isNewerThan(current), isFalse);
      expect(AppVersion.tryParse('0.5')!.isNewerThan(current), isTrue);
      expect(current.equals(AppVersion.tryParse('0.4.3.0')!), isTrue);
    });

    test('未知版本不参与「更新」判断', () {
      expect(AppVersion.unknown.isNewerThan(current), isFalse);
      expect(current.isNewerThan(AppVersion.unknown), isTrue);
      expect(AppVersion.unknown.compareTo(AppVersion.unknown), 0);
    });

    test('display 保留段数', () {
      expect(AppVersion.tryParse('v0.3.3.1')!.display, 'v0.3.3.1');
      expect(AppVersion.tryParse('0.4.0')!.display, 'v0.4');
      expect(AppVersion.unknown.display, '未知版本');
    });
  });
}
