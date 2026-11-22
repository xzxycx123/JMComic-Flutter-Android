import 'package:flutter/foundation.dart';

/// 应用版本号（`0.4.3` / `v0.4.3` / `0.3.3.1` 都能解析）。
///
/// GitHub Release 的 tag 命名不统一（本仓库既有 `v0.4.3` 也有 `0.4.0`），
/// 所以这里只认「点分数字」：前缀 `v` / `release-`、后缀 `-beta` / `+11`
/// 全部丢掉；段数不够时按 0 补齐再逐段比较（`0.3.3.1` > `0.3.3`）。
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.segments, {this.raw = '', this.prerelease = false});

  /// 逐段数字（从高位到低位），已去掉尾部纯 0 段。
  final List<int> segments;

  /// 解析时的原始字符串（展示用，比如 `v0.4.3`）。
  final String raw;

  /// tag 带 `-alpha` / `-beta` / `-rc` 这类预发布后缀。
  final bool prerelease;

  static const AppVersion unknown =
      AppVersion(<int>[], raw: 'unknown', prerelease: false);

  /// 解析失败返回 null（这类 tag 直接跳过，不参与「有没有新版本」判断）。
  static AppVersion? tryParse(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    // 只取第一个「点分数字」核心：`v0.4.3` / `release-0.4.0` / `JMComic-v0.3.3.1` 都命中。
    final match = RegExp(r'\d+(?:\.\d+)*').firstMatch(text);
    if (match == null) return null;
    final segments = <int>[];
    for (final part in match.group(0)!.split('.')) {
      segments.add(int.parse(part));
    }
    while (segments.length > 1 && segments.last == 0) {
      segments.removeLast();
    }
    return AppVersion(
      List<int>.unmodifiable(segments),
      raw: text,
      // 版本号核心后面紧跟 `-` 才算预发布（`+11` 构建号不算）。
      prerelease: text.substring(match.end).startsWith('-'),
    );
  }

  bool get isKnown => segments.isNotEmpty;

  /// 用于展示：`v0.4.3`。
  String get display => isKnown ? 'v${segments.join('.')}' : '未知版本';

  /// 同 [display]，但没有 `v` 前缀，便于写进文件名 / 注释。
  String get plain => segments.join('.');

  /// 严格大于 [other] 才算更新（段数不同按 0 补齐）。
  bool isNewerThan(AppVersion other) {
    if (!isKnown) return false;
    if (!other.isKnown) return true;
    final length = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var index = 0; index < length; index++) {
      final left = index < segments.length ? segments[index] : 0;
      final right = index < other.segments.length ? other.segments[index] : 0;
      if (left != right) return left > right;
    }
    return false;
  }

  bool equals(AppVersion other) =>
      isKnown && other.isKnown && _sameSegments(other);

  bool _sameSegments(AppVersion other) {
    final length = segments.length > other.segments.length
        ? segments.length
        : other.segments.length;
    for (var index = 0; index < length; index++) {
      final left = index < segments.length ? segments[index] : 0;
      final right = index < other.segments.length ? other.segments[index] : 0;
      if (left != right) return false;
    }
    return true;
  }

  @override
  int compareTo(AppVersion other) {
    if (!isKnown && !other.isKnown) return 0;
    if (!isKnown) return -1;
    if (!other.isKnown) return 1;
    if (isNewerThan(other)) return 1;
    return _sameSegments(other) ? 0 : -1;
  }

  @override
  bool operator ==(Object other) => other is AppVersion && _sameSegments(other);

  @override
  int get hashCode => Object.hashAll(segments);

  @override
  String toString() => display;
}
