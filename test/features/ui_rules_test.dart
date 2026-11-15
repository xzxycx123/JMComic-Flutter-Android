import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// UI 守卫：lib/ 内不得出现 emoji、不得使用 Icons.* 图标字体。
///
/// 与 tools/check_ui_rules.ps1 等价，作为 `flutter test` 的最后一道门。
void main() {
  final emojiPatterns = <RegExp>[
    RegExp(r'[\u2190-\u21FF\u2300-\u27BF\u2B00-\u2BFF\uFE0F]'),
    RegExp(r'[\uD83C-\uD83E][\uDC00-\uDFFF]'),
  ];
  final iconsPattern = RegExp(r'\bIcons\.[A-Za-z_]');

  List<File> dartFiles() {
    final dir = Directory('lib');
    if (!dir.existsSync()) return const <File>[];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);
  }

  test('lib/ 内没有 Icons.* 图标字体调用', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (iconsPattern.hasMatch(line) && !line.contains('ui-rules-ignore')) {
          offenders.add('${file.path}:${index + 1}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('lib/ 内没有 emoji / 装饰符号', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line.contains('ui-rules-ignore')) continue;
        for (final pattern in emojiPatterns) {
          if (pattern.hasMatch(line)) {
            offenders.add('${file.path}:${index + 1}');
            break;
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('图标资源全部是 svg', () {
    final dir = Directory('assets/icons');
    final files = dir
        .listSync()
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => !path.endsWith('.svg'))
        .toList(growable: false);
    expect(files, isEmpty);
  });

  test('assets/ 内的 svg / md 也没有 emoji（与 check_ui_rules.ps1 等价）', () {
    final dir = Directory('assets');
    if (!dir.existsSync()) return;
    final offenders = <String>[];
    for (final file in dir.listSync(recursive: true).whereType<File>()) {
      if (!const <String>['.svg', '.md', '.yaml', '.html'].contains(_ext(file.path))) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        if (lines[index].contains('ui-rules-ignore')) continue;
        for (final pattern in emojiPatterns) {
          if (pattern.hasMatch(lines[index])) {
            offenders.add('${file.path}:${index + 1}');
            break;
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}

String _ext(String path) {
  final dot = path.lastIndexOf('.');
  return dot < 0 ? '' : path.substring(dot);
}
