/// PDF 命名清洗（与 `JmScript/util/FileNames.kt` 同语义）。
library;

final RegExp _reserved = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]');
final RegExp _repeatedSpaces = RegExp(r'\s+');
final RegExp _edgeDotsOrSpaces = RegExp(r'^[. ]+|[. ]+$');

/// `JM{id} - {标题}.pdf`
///
/// 规则：非法字符 -> `_`、空白折叠成单空格、去首尾 `.` 与空格、按码点截断 80、空标题 `comic`。
String pdfName(String albumId, String title) {
  var clean =
      title.replaceAll(_reserved, '_').replaceAll(_repeatedSpaces, ' ').trim();
  clean = clean.replaceAll(_edgeDotsOrSpaces, '');
  clean = trimToCodePoints(clean, 80);
  if (clean.isEmpty) clean = 'comic';
  return 'JM$albumId - $clean.pdf';
}

/// 同名 -> `名称 (2).pdf`，`(3)` … 依次递增。
String nextAvailablePdfName(String requested, Iterable<String> existing) {
  final taken = existing.toSet();
  if (!taken.contains(requested)) return requested;
  final base = requested.endsWith('.pdf')
      ? requested.substring(0, requested.length - 4)
      : requested;
  var suffix = 2;
  while (taken.contains('$base ($suffix).pdf')) {
    suffix++;
  }
  return '$base ($suffix).pdf';
}

/// 按 Unicode 码点截断，emoji 不会被劈成半个代理对。
String trimToCodePoints(String input, int maxCount) {
  final runes = input.runes.toList(growable: false);
  if (runes.length <= maxCount) return input;
  return String.fromCharCodes(runes.take(maxCount)).trimRight();
}

/// 文件系统允许的安全名（用于临时目录 / 章节目录）。
String safeSegment(String input, {int maxCodePoints = 40}) {
  final clean = input
      .replaceAll(_reserved, '_')
      .replaceAll(_repeatedSpaces, ' ')
      .trim()
      .replaceAll(_edgeDotsOrSpaces, '');
  final trimmed = trimToCodePoints(clean, maxCodePoints);
  return trimmed.isEmpty ? 'untitled' : trimmed;
}

/// 阅读器「下载当页图片」的默认目录（相对公共 Pictures；设置页可改）。
const String defaultSaveImageDir = 'Pictures/JMComicDownloader';

/// 统一保存目录写法：`\` 归一成 `/`、折叠重复斜杠、去掉首尾斜杠；空值回落默认目录。
String normalizeSaveDir(String input) {
  var value = input.trim().replaceAll('\\', '/');
  value = value.replaceAll(RegExp(r'/+'), '/');
  value = value.replaceAll(RegExp(r'^/+|/+$'), '');
  return value.isEmpty ? defaultSaveImageDir : value;
}

final RegExp _chapterNumber = RegExp(r'第\s*([0-9]+)\s*[话話章回卷]');

/// 章节名转成文件名里的「第几章」：能解析出数字就用 `第N章`，否则用清洗后的标题。
String chapterFileLabel(String title) {
  final match = _chapterNumber.firstMatch(title);
  if (match != null) return '第${match.group(1)}章';
  final clean = safeSegment(title, maxCodePoints: 24).replaceAll(' ', '');
  return clean == 'untitled' ? '第1章' : clean;
}

/// 阅读器当页图片命名：`JMComic-{jm编号}-{第几章}-{第几页}.png`。
String readerImageName({
  required String albumId,
  required String chapterTitle,
  required int page,
  String extension = 'png',
}) {
  final album = safeSegment(albumId, maxCodePoints: 24);
  return 'JMComic-$album-${chapterFileLabel(chapterTitle)}-第$page页.$extension';
}
