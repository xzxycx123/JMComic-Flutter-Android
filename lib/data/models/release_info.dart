import 'package:flutter/foundation.dart';

import 'app_version.dart';
import 'release_notes.dart';

/// Release 附件（本仓库只发 universal APK，取第一个 `.apk`）。
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.sizeBytes = 0,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  String get sizeText {
    if (sizeBytes <= 0) return '';
    const unit = 1024 * 1024;
    if (sizeBytes >= unit) {
      return '${(sizeBytes / unit).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// 一次 GitHub Release 的展示快照。
@immutable
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    this.apk,
    this.publishedAt,
    this.prerelease = false,
  });

  /// 原始 tag，例如 `v0.4.3` / `0.4.0`。
  final String tag;
  final AppVersion version;
  final String title;

  /// Release 页正文（readme），已归一成 block。
  final ReleaseNotes notes;

  /// 发布页地址（安装失败时的兜底入口）。
  final String htmlUrl;
  final ReleaseAsset? apk;
  final DateTime? publishedAt;
  final bool prerelease;

  String get versionLabel => version.isKnown ? version.display : tag;

  String get publishedLabel {
    final date = publishedAt;
    if (date == null) return '';
    final local = date.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }

  @override
  String toString() => 'ReleaseInfo($tag, apk=${apk?.name})';
}
