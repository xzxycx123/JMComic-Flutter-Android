import '../../data/models/jm_comment.dart';

/// 评论广告过滤阈值：正文里 emoji 数量 **大于** [kAdEmojiThreshold] 才算可能广告。
///
/// 即 2 个仍展示、3 个开始隐藏（列表里常见「好看到爆 emoji emoji」这类刷屏广告）。
const int kAdEmojiThreshold = 2;

/// [countEmoji] 的便捷判定：正文 emoji 数是否超过阈值。
bool looksLikeAdComment(String content, {int threshold = kAdEmojiThreshold}) =>
    countEmoji(content) > threshold;

/// 统计文本里的 emoji 个数。
///
/// 规则（与 `test/features/album_comment_filter_test.dart` 对齐）：
/// - 一个 ZWJ 序列算 1（一家三口的组合图形 = 1，组成成员不重复计数）；
/// - variation selector（U+FE0E/U+FE0F）、肤色修饰（U+1F3FB–U+1F3FF）、
///   tag 字符（U+E0020–U+E007F）都算 base 的一部分，不单独计数；
/// - 区域指示符成对（国旗）算 1；
/// - 数字/#/* + U+FE0F + U+20E3 这种 keycap 算 1；
/// - `©®™` 这类文本型符号只有带 U+FE0F（emoji 呈现）时才算。
int countEmoji(String text) {
  if (text.isEmpty) return 0;
  final runes = text.runes.toList(growable: false);
  var count = 0;
  var index = 0;
  while (index < runes.length) {
    final codePoint = runes[index];
    if (_isRegionalIndicator(codePoint)) {
      // 两个区域指示符合成一面旗帜，按 1 算。
      final paired =
          index + 1 < runes.length && _isRegionalIndicator(runes[index + 1]);
      count++;
      index += paired ? 2 : 1;
      continue;
    }
    final variationEmoji = index + 1 < runes.length &&
        runes[index + 1] == _vs16 &&
        _isVariationOnlyBase(codePoint);
    if (_isEmojiBase(codePoint) || variationEmoji) {
      index++;
      // 吞掉后续的修饰符与 ZWJ 连接序列，整串只算 1 个。
      while (index < runes.length) {
        final next = runes[index];
        if (_isEmojiModifier(next)) {
          index++;
          continue;
        }
        if (next == _zwj) {
          index++;
          if (index < runes.length &&
              (_isEmojiBase(runes[index]) ||
                  _isRegionalIndicator(runes[index]))) {
            index++;
          }
          continue;
        }
        break;
      }
      count++;
      continue;
    }
    // keycap：数字 / # / * 后面跟 U+FE0F? U+20E3。
    if (_isKeycapBase(codePoint)) {
      var lookahead = index + 1;
      if (lookahead < runes.length && runes[lookahead] == _vs16) lookahead++;
      if (lookahead < runes.length && runes[lookahead] == _keycap) {
        count++;
        index = lookahead + 1;
        continue;
      }
    }
    index++;
  }
  return count;
}

/// 按 emoji 数量过滤评论（只生成视图，不改服务端返回的原始列表与 total）。
class CommentFilter {
  const CommentFilter({
    this.showHidden = false,
    this.threshold = kAdEmojiThreshold,
  });

  /// 用户是否点了「显示可能存在广告的评论」。
  final bool showHidden;
  final int threshold;

  /// 这一条是否属于「可能广告」。
  bool shouldHide(JmComment comment) => countEmoji(comment.content) > threshold;

  /// 顶层评论的可见视图；[showHidden] 为 true 时保持原顺序全量返回。
  List<JmComment> apply(List<JmComment> items) {
    if (showHidden) return items;
    return items.where((item) => !shouldHide(item)).toList(growable: false);
  }

  /// 某条评论的回复可见视图（replies 同样按 emoji 过滤）。
  List<JmComment> repliesOf(JmComment parent) {
    if (showHidden) return parent.replies;
    return parent.replies
        .where((reply) => !shouldHide(reply))
        .toList(growable: false);
  }

  /// 顶层 + replies 里被隐藏的条数（与 [showHidden] 无关，用于按钮显隐）。
  int hiddenCount(List<JmComment> items) {
    var hidden = 0;
    for (final item in items) {
      if (shouldHide(item)) hidden++;
      for (final reply in item.replies) {
        if (shouldHide(reply)) hidden++;
      }
    }
    return hidden;
  }
}

const int _zwj = 0x200D;
const int _vs15 = 0xFE0E;
const int _vs16 = 0xFE0F;
const int _keycap = 0x20E3;

bool _isRegionalIndicator(int codePoint) =>
    codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;

bool _isKeycapBase(int codePoint) =>
    codePoint == 0x23 || // #
    codePoint == 0x2A || // *
    (codePoint >= 0x30 && codePoint <= 0x39); // 0-9

/// 只有带上 U+FE0F 才算 emoji 的「文本型」符号。
bool _isVariationOnlyBase(int codePoint) =>
    codePoint == 0x00A9 || // ©
    codePoint == 0x00AE || // ®
    codePoint == 0x203C || // ‼
    codePoint == 0x2049 || // ⁉
    codePoint == 0x2122 || // ™
    codePoint == 0x2139 || // ℹ
    codePoint == 0x3030 ||
    codePoint == 0x303D ||
    codePoint == 0x3297 ||
    codePoint == 0x3299;

bool _isEmojiModifier(int codePoint) =>
    codePoint == _vs15 ||
    codePoint == _vs16 ||
    (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF) ||
    (codePoint >= 0xE0020 && codePoint <= 0xE007F);

/// 常见 emoji 基字符（含非 emoji 呈现的字形，只要属于 pictograph 区就算）。
bool _isEmojiBase(int codePoint) {
  if (codePoint >= 0x1F000 && codePoint <= 0x1F0FF) return true; // 麻将/纸牌
  if (codePoint >= 0x1F100 && codePoint <= 0x1F1E5) return true; // 带圈字母补充
  if (codePoint >= 0x1F200 && codePoint <= 0x1F2FF) return true; // 带框汉字
  if (codePoint >= 0x1F300 && codePoint <= 0x1F5FF) return true; // 杂项象形
  if (codePoint >= 0x1F600 && codePoint <= 0x1F64F) return true; // 表情
  if (codePoint >= 0x1F680 && codePoint <= 0x1F6FF) return true; // 交通
  if (codePoint >= 0x1F900 && codePoint <= 0x1F9FF) return true; // 补充符号
  if (codePoint >= 0x1FA70 && codePoint <= 0x1FAFF) return true; // 扩展 A
  if (codePoint >= 0x2600 && codePoint <= 0x27BF) return true; // 杂项/装饰
  if (codePoint >= 0x2B00 && codePoint <= 0x2BFF) return true; // 星形/方框
  if (codePoint >= 0x231A && codePoint <= 0x231B) return true; // 手表/沙漏
  if (codePoint >= 0x23E9 && codePoint <= 0x23FA) return true; // 媒体控制
  if (codePoint >= 0x25AA && codePoint <= 0x25FE) return true; // 几何图形
  if (codePoint >= 0x2934 && codePoint <= 0x2935) return true; // 弯箭头
  if (codePoint >= 0x3030 && codePoint <= 0x303D) return true;
  if (codePoint == 0x3297 || codePoint == 0x3299) return true;
  return false;
}
