/// 作者名规范化。
///
/// JM 的 `author` 字段偶尔会写成 `[作者名]` / `【作者名】` 这种包着中括号的形式：
/// 直接显示会多出一层括号，拿去做关键词搜索又会把 `[` `]` 一起发出去，服务端
/// 匹配不到作者，结果自然是空列表。这里统一剥掉方括号类符号并收敛空白。
///
/// 多作者（`[A], [B]`）会变成 `A, B`；只有落单括号也会被去掉。
String normalizeAuthorName(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  if (!_brackets.hasMatch(value)) return value;
  return value
      .replaceAll(_brackets, ' ')
      .replaceAllMapped(_cjkSeparator, (match) => match.group(1)!)
      .replaceAllMapped(_spaceBeforeSeparator, (match) => match.group(1)!)
      .replaceAll(_spaces, ' ')
      .trim();
}

/// 半角 / 全角方括号、书名号式方括号（`[]`、`［］`、`【】`、`〔〕`）。
final RegExp _brackets = RegExp(r'[\[\]［］【】〔〕]');

/// 中文分隔符（`，`、`、`）前后都不留空格。
final RegExp _cjkSeparator = RegExp(r'\s*([，、])\s*');

/// 半角逗号前的空格去掉，后面的保留一个。
final RegExp _spaceBeforeSeparator = RegExp(r'\s+([,])');

final RegExp _spaces = RegExp(r'\s+');
