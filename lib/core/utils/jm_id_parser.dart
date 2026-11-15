/// 车号解析 / 批量分词（与 `JmScript/util/JmIdParser.kt` 同语义）。
library;

final RegExp _pathId = RegExp(r'/(?:album|photo)/(\d+)', caseSensitive: false);
final RegExp _queryId =
    RegExp(r'[?&](?:id|album_id|photo_id|aid)=(\d+)', caseSensitive: false);
final RegExp _plainId = RegExp(r'^(?:JM)?\s*(\d+)$', caseSensitive: false);
final RegExp _digits = RegExp(r'\d+');
final RegExp _separators = RegExp(r'[\s,，、;；]+');

/// 单个输入 -> 车号；无法判定返回 null。
String? parseJmId(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;

  final candidate = _pathId.firstMatch(value)?.group(1) ??
      _queryId.firstMatch(value)?.group(1) ??
      _plainId.firstMatch(value)?.group(1) ??
      _digits.firstMatch(value)?.group(0);
  if (candidate == null) return null;

  final normalized = candidate.replaceFirst(RegExp(r'^0+'), '');
  final result = normalized.isEmpty ? '0' : normalized;
  return (result == '0' || result.length > 10) ? null : result;
}

/// 批量输入 -> 词条（按换行 / 逗号 / 顿号 / 分号 / 空格切）。
List<String> tokenizeJmIds(String input) => input
    .split(_separators)
    .map((token) => token.trim())
    .where((token) => token.isNotEmpty)
    .toList(growable: false);

/// 批量输入 -> 去重保序的车号表。
List<String> parseJmIds(String input) {
  final seen = <String>{};
  final result = <String>[];
  for (final token in tokenizeJmIds(input)) {
    final id = parseJmId(token);
    if (id == null) continue;
    if (seen.add(id)) result.add(id);
  }
  return result;
}

/// 批量输入的解析预览（用于下载页「解析预览」文案）。
class JmIdPreview {
  const JmIdPreview({
    required this.ids,
    required this.total,
    required this.ignored,
  });

  final List<String> ids;
  final int total;
  final int ignored;

  bool get isEmpty => ids.isEmpty;

  String get label {
    if (total == 0) return '等待输入';
    return '解析预览：${ids.length} 个有效 · $ignored 个忽略';
  }
}

JmIdPreview previewJmIds(String input) {
  final tokens = tokenizeJmIds(input);
  final ids = parseJmIds(input);
  return JmIdPreview(
    ids: ids,
    total: tokens.length,
    ignored: tokens.length - ids.length,
  );
}
