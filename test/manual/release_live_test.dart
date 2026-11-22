@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/config/app_config.dart';
import 'package:jm_comic/data/models/app_version.dart';
import 'package:jm_comic/data/sources/github_release_client.dart';

/// 实网联调：真的去 GitHub 发布页取一次版本（默认跳过，CI 不跑）。
///
/// ```powershell
/// flutter test --dart-define=JM_LIVE=true test/manual/release_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('JM_LIVE');

void main() {
  test(
    '实网：读取 releases（API 被限流时自动走 atom）',
    () async {
      final client = GithubReleaseClient();
      final releases = await client.fetchReleases();

      // ignore: avoid_print
      print('共 ${releases.length} 个 release');
      for (final release in releases.take(5)) {
        // ignore: avoid_print
        print(
          '${release.tag.padRight(10)} apk=${release.apk?.name ?? '-'} '
          'notes=${release.notes.blocks.length} 块 published=${release.publishedLabel}',
        );
      }

      expect(releases, isNotEmpty, reason: '发布页读不到：先查网络 / 代理');
      expect(
        releases.any((release) => release.version.isKnown),
        isTrue,
        reason: 'tag 至少要能解析出版本号',
      );
      final newest = GithubReleaseClient.pickNewest(
        releases,
        AppVersion.tryParse('0.0.1')!,
      );
      expect(newest, isNotNull);
      // ignore: avoid_print
      print('发布会挑中的最新版：${newest!.tag} (${AppConfig.releasesPageUrl})');

      // atom 兜底没有附件信息：确认 assets 面板能补出 APK 直链。
      final asset = await client.fetchApkAsset(newest);
      // ignore: avoid_print
      print('APK 直链：${asset?.downloadUrl ?? '未找到'}');
      expect(asset, isNotNull, reason: 'expanded_assets 里应该能拿到 .apk 直链');
      expect(asset!.downloadUrl, endsWith('.apk'));
    },
    skip: _live ? false : '实网用例默认跳过，加 --dart-define=JM_LIVE=true 才跑',
  );
}
