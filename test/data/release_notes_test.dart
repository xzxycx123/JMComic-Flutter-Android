import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/release_notes.dart';

void main() {
  group('ReleaseNotes.markdown', () {
    final notes = ReleaseNotes.markdown(
      '# JMComic v0.4.4\n'
      '\n'
      '> 一句说明\n'
      '\n'
      '## bug修复\n'
      '\n'
      '- 修复**首页**点赞数\n'
      '- 解决 `Liquid Glass` 色散问题\n'
      '\n'
      '## 功能添加\n'
      '\n'
      '1. 添加保存当前图\n'
      '2. 添加结束页\n'
      '\n'
      '| 项 | 值 |\n'
      '|---|---|\n'
      '| 产物 | `JMComic-0.4.4-release.apk` |\n'
      '\n'
      '```\n'
      'flutter build apk --release\n'
      '```\n'
      '\n'
      '---\n'
      '\n'
      '尾部说明 [仓库](https://example.com)\n',
    );

    test('标题层级与文本', () {
      final headings = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.heading)
          .toList(growable: false);
      expect(headings.map((block) => block.text).toList(), <String>[
        'JMComic v0.4.4',
        'bug修复',
        '功能添加',
      ]);
      expect(headings.first.level, 1);
      expect(headings[1].level, 2);
    });

    test('引用 / 列表 / 有序列表', () {
      final quote = notes.blocks
          .firstWhere((block) => block.kind == ReleaseNoteKind.quote);
      expect(quote.text, '一句说明');

      final bullets = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.bullet)
          .map((block) => block.text)
          .toList(growable: false);
      // 两条项目符号 + 表格行（表头分隔行被丢掉）
      expect(bullets, contains('修复首页点赞数'));
      expect(bullets, contains('解决 Liquid Glass 色散问题'));
      expect(bullets, contains('项 · 值'));
      expect(bullets, contains('产物 · JMComic-0.4.4-release.apk'));

      final ordered = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.ordered)
          .toList(growable: false);
      expect(ordered.map((block) => block.index).toList(), <int>[1, 2]);
      expect(ordered.first.text, '添加保存当前图');
    });

    test('代码块与分隔线', () {
      final code =
          notes.blocks.firstWhere((block) => block.kind == ReleaseNoteKind.code);
      expect(code.text, 'flutter build apk --release');
      expect(
        notes.blocks.any((block) => block.kind == ReleaseNoteKind.divider),
        isTrue,
      );
    });

    test('链接只留文字，正文里没有 markdown 标记', () {
      final plain = notes.plainText;
      expect(plain, contains('仓库'));
      expect(plain, isNot(contains('**')));
      expect(plain, isNot(contains('](http')));
    });

    test('空正文得到空 block 列表', () {
      expect(ReleaseNotes.markdown('').isEmpty, isTrue);
      expect(ReleaseNotes.empty.isEmpty, isTrue);
    });
  });

  group('ReleaseNotes.html（atom 兜底）', () {
    final notes = ReleaseNotes.html(
      '<h1>JMComic v0.4.4</h1>'
      '<p>添加结束页</p>'
      '<h2>bug修复</h2>'
      '<ul><li>修复首页点赞数</li><li>解决色散问题</li></ul>'
      '<blockquote><p>一句说明</p></blockquote>'
      '<pre><code>flutter build apk</code></pre>'
      '<hr>'
      '<table><tr><th>项</th><th>值</th></tr>'
      '<tr><td>产物</td><td>apk</td></tr></table>',
    );

    test('标题 / 段落 / 列表 / 代码 / 表格都能落到 block', () {
      final headings = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.heading)
          .map((block) => block.text)
          .toList(growable: false);
      expect(headings, <String>['JMComic v0.4.4', 'bug修复']);

      final paragraphs = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.paragraph)
          .map((block) => block.text)
          .toList(growable: false);
      expect(paragraphs, contains('添加结束页'));

      final bullets = notes.blocks
          .where((block) => block.kind == ReleaseNoteKind.bullet)
          .map((block) => block.text)
          .toList(growable: false);
      expect(bullets, containsAll(<String>['修复首页点赞数', '解决色散问题', '项 · 值', '产物 · apk']));

      final code =
          notes.blocks.firstWhere((block) => block.kind == ReleaseNoteKind.code);
      expect(code.text.trim(), 'flutter build apk');

      expect(
        notes.blocks.any((block) => block.kind == ReleaseNoteKind.quote),
        isTrue,
      );
      expect(
        notes.blocks.any((block) => block.kind == ReleaseNoteKind.divider),
        isTrue,
      );
    });
  });
}
