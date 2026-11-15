/// JSON 取值工具：对齐 Gson 的 `asString` 语义（数字 / 布尔也能安全转字符串）。
library;

String? asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is num) {
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
  if (value is bool) return value ? 'true' : 'false';
  return value.toString();
}

String asStringOr(dynamic value, String fallback) {
  final text = asString(value)?.trim();
  return (text == null || text.isEmpty) ? fallback : text;
}

int asInt(dynamic value, [int fallback = 0]) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
    final asDouble = double.tryParse(value.trim());
    if (asDouble != null) return asDouble.toInt();
    return fallback;
  }
  if (value is bool) return value ? 1 : 0;
  return fallback;
}

bool asBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }
  return false;
}

Map<String, dynamic>? asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry('$key', item));
  }
  return null;
}

List<dynamic> asList(dynamic value) {
  if (value is List) return value;
  return const <dynamic>[];
}

List<String> asStringList(dynamic value) {
  return asList(value)
      .map((item) => asString(item))
      .whereType<String>()
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

/// 逗号/斜杠分隔的 tag 字符串 -> 列表（`tags` 有时是数组有时是字符串）。
List<String> asTagList(dynamic value) {
  if (value is String) {
    return value
        .split(RegExp(r'[,，、/|]+'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
  return asStringList(value);
}
