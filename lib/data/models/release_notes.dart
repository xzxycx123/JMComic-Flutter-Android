import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// 发布说明里的一块内容（标题 / 段落 / 列表 / 引用 / 代码）。
enum ReleaseNoteKind {
  heading,
  paragraph,
  bullet,
  ordered,
  quote,
  code,
  divider
}

@immutable
class ReleaseNoteBlock {
  const ReleaseNoteBlock(
    this.kind,
    this.text, {
    this.level = 0,
    this.index = 1,
  });

  final ReleaseNoteKind kind;

  /// 已去掉 markdown 标记的纯文本（行内 `**` / 反引号 / 链接保留文字）。
  final String text;

  /// 标题层级（1-6）。
  final int level;

  /// 有序列表的序号。
  final int index;

  @override
  String toString() => '${kind.name}($text)';
}

/// Release 页的 readme（GitHub 上那段正文）。
///
/// 两个来源：
/// - REST API 的 `body` 是 **Markdown**；
/// - `releases.atom` 的 `content` 是 **HTML**（API 被限流时的兜底）。
///
/// 都归一成 [ReleaseNoteBlock] 列表，UI 层只负责排版，两套主题共用。
@immutable
class ReleaseNotes {
  const ReleaseNotes(this.blocks);

  static const ReleaseNotes empty = ReleaseNotes(<ReleaseNoteBlock>[]);

  final List<ReleaseNoteBlock> blocks;

  bool get isEmpty => blocks.isEmpty;

  bool get isNotEmpty => blocks.isNotEmpty;

  /// 纯文本（复制 / 无障碍朗读用）。
  String get plainText => blocks.map((block) => block.text).join('\n');

  // ------------------------------------------------------------- Markdown
  factory ReleaseNotes.markdown(String source) =>
      ReleaseNotes(_markdownBlocks(source));

  static List<ReleaseNoteBlock> _markdownBlocks(String source) {
    final blocks = <ReleaseNoteBlock>[];
    final lines =
        source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final paragraph = <String>[];
    var index = 0;

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final text = _joinInlineText(paragraph);
      paragraph.clear();
      if (text.isNotEmpty) {
        blocks.add(ReleaseNoteBlock(ReleaseNoteKind.paragraph, text));
      }
    }

    void add(
      ReleaseNoteKind kind,
      String text, {
      int level = 0,
      int index = 1,
    }) {
      blocks.add(ReleaseNoteBlock(kind, text, level: level, index: index));
    }

    while (index < lines.length) {
      final raw = lines[index];
      final line = raw.trimRight();
      final trimmed = line.trim();

      // 围栏代码块
      if (trimmed.startsWith('```')) {
        flushParagraph();
        final code = <String>[];
        index++;
        while (index < lines.length && !lines[index].trim().startsWith('```')) {
          code.add(lines[index]);
          index++;
        }
        index++; // 跳过收尾围栏
        blocks.add(ReleaseNoteBlock(ReleaseNoteKind.code, code.join('\n')));
        continue;
      }

      if (trimmed.isEmpty) {
        flushParagraph();
        index++;
        continue;
      }

      // 分隔线
      if (RegExp(r'^([-*_])(\s*\1){2,}$').hasMatch(trimmed)) {
        flushParagraph();
        blocks.add(const ReleaseNoteBlock(ReleaseNoteKind.divider, ''));
        index++;
        continue;
      }

      // 标题
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        flushParagraph();
        add(
          ReleaseNoteKind.heading,
          _inlineText(heading.group(2)!),
          level: heading.group(1)!.length,
        );
        index++;
        continue;
      }

      // 引用块
      if (trimmed.startsWith('>')) {
        flushParagraph();
        final quote = <String>[];
        while (index < lines.length && lines[index].trim().startsWith('>')) {
          quote.add(lines[index].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          index++;
        }
        add(ReleaseNoteKind.quote, _joinInlineText(quote));
        continue;
      }

      // 表格：`|---|---|` 这类分隔行丢掉，其余按「单元格 · 单元格」排成条目。
      if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
        flushParagraph();
        if (!RegExp(r'^\|[\s:|-]+\|$').hasMatch(trimmed)) {
          final cells = trimmed
              .split('|')
              .map((cell) => _inlineText(cell))
              .where((cell) => cell.isNotEmpty)
              .toList(growable: false);
          if (cells.isNotEmpty) {
            add(ReleaseNoteKind.bullet, cells.join(' · '));
          }
        }
        index++;
        continue;
      }

      // 无序列表
      final bullet = RegExp(r'^[-*+]\s+(.*)$').firstMatch(trimmed);
      if (bullet != null) {
        flushParagraph();
        add(ReleaseNoteKind.bullet, _inlineText(bullet.group(1)!));
        index++;
        continue;
      }

      // 有序列表
      final ordered = RegExp(r'^(\d{1,3})[.)]\s+(.*)$').firstMatch(trimmed);
      if (ordered != null) {
        flushParagraph();
        add(
          ReleaseNoteKind.ordered,
          _inlineText(ordered.group(2)!),
          index: int.tryParse(ordered.group(1)!) ?? 1,
        );
        index++;
        continue;
      }

      paragraph.add(trimmed);
      index++;
    }
    flushParagraph();
    return blocks;
  }

  /// 一段里可能有多行（markdown 软换行），拼成一行再清行内标记。
  static String _joinInlineText(List<String> lines) =>
      _inlineText(lines.join(' '));

  /// 去掉行内标记，只留可读文本：`**b**` -> b，`` `c` `` -> c，`[t](u)` -> t。
  static String _inlineText(String source) {
    var text = source;
    text = text.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]*)\]\([^)]*\)'),
      (match) => match.group(1) ?? '',
    );
    text = text.replaceAll('**', '');
    text = text.replaceAll('__', '');
    text = text.replaceAll('`', '');
    text = text.replaceAll('<br>', ' ');
    text = text.replaceAll('<br/>', ' ');
    // 单个 `*` / `_` 只作为强调标记出现时才清掉，避免误伤 `0.4.3_1`。
    text = text.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9])\*([^*]+)\*(?![A-Za-z0-9])'),
      (match) => match.group(1)!,
    );
    text = text.replaceAll(RegExp(r'[\u00A0\u200B]'), ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ----------------------------------------------------------------- HTML
  /// `releases.atom` 的 `<content type="html">`：解析成同一套 block。
  factory ReleaseNotes.html(String source) => ReleaseNotes(_htmlBlocks(source));

  static List<ReleaseNoteBlock> _htmlBlocks(String source) {
    final document = html_parser.parseFragment(source);
    final blocks = <ReleaseNoteBlock>[];

    void addText(
      ReleaseNoteKind kind,
      String text, {
      int level = 0,
      int index = 1,
    }) {
      final cleaned = _inlineText(text);
      if (cleaned.isEmpty) return;
      blocks.add(ReleaseNoteBlock(kind, cleaned, level: level, index: index));
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        final text = node.text;
        if (text.trim().isNotEmpty) addText(ReleaseNoteKind.paragraph, text);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      final heading = RegExp(r'^h([1-6])$').firstMatch(tag);
      if (heading != null) {
        addText(
          ReleaseNoteKind.heading,
          node.text,
          level: int.parse(heading.group(1)!),
        );
        return;
      }
      switch (tag) {
        case 'ul':
          for (final item in node.children.where((e) => e.localName == 'li')) {
            addText(ReleaseNoteKind.bullet, item.text);
          }
          return;
        case 'ol':
          var index = 1;
          for (final item in node.children.where((e) => e.localName == 'li')) {
            addText(ReleaseNoteKind.ordered, item.text, index: index);
            index++;
          }
          return;
        case 'li':
          addText(ReleaseNoteKind.bullet, node.text);
          return;
        case 'blockquote':
          addText(ReleaseNoteKind.quote, node.text);
          return;
        case 'pre':
          blocks.add(
            ReleaseNoteBlock(ReleaseNoteKind.code, node.text.trimRight()),
          );
          return;
        case 'hr':
          blocks.add(const ReleaseNoteBlock(ReleaseNoteKind.divider, ''));
          return;
        case 'table':
          for (final row in node.querySelectorAll('tr')) {
            final cells = row.children
                .where(
                  (cell) => cell.localName == 'td' || cell.localName == 'th',
                )
                .map((cell) => _inlineText(cell.text))
                .where((cell) => cell.isNotEmpty)
                .toList(growable: false);
            if (cells.isNotEmpty) {
              addText(ReleaseNoteKind.bullet, cells.join(' · '));
            }
          }
          return;
        case 'p':
        case 'div':
        case 'section':
        case 'article':
        case 'body':
          // 容器：直接递归，文本节点自己会落成段落。
          for (final child in node.nodes) {
            walk(child);
          }
          return;
        default:
          // strong / em / a / code / span / br 之类当作文本处理。
          if (node.text.trim().isNotEmpty) {
            addText(ReleaseNoteKind.paragraph, node.text);
          }
      }
    }

    for (final node in document.nodes) {
      walk(node);
    }
    return blocks;
  }
}
