import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:jm_comic/data/models/app_version.dart';
import 'package:jm_comic/data/models/release_info.dart';
import 'package:jm_comic/data/models/release_notes.dart';
import 'package:jm_comic/data/sources/github_release_client.dart';

Dio _testDio() => Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        headers: <String, dynamic>{'User-Agent': 'test'},
      ),
    );

String _apiPayload() => jsonEncode(<Map<String, dynamic>>[
      <String, dynamic>{
        'tag_name': 'v0.3.3.1',
        'name': 'JMComic 0.3.3.1',
        'body': '## 重发\n\n- toast 收尾',
        'html_url': 'https://github.com/x/1',
        'draft': false,
        'prerelease': false,
        'published_at': '2026-11-20T15:46:53Z',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'JMComic-0.3.3.1-release.apk',
            'browser_download_url': 'https://example.com/a.apk',
            'size': 68412713,
          },
        ],
      },
      <String, dynamic>{
        'tag_name': 'v0.4.4',
        'name': 'JMComic v0.4.4',
        'body': '# JMComic v0.4.4\n\n添加结束页',
        'html_url': 'https://github.com/x/2',
        'draft': false,
        'prerelease': false,
        'published_at': '2026-11-23T09:00:00Z',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'notes.txt',
            'browser_download_url': 'https://example.com/notes.txt',
            'size': 12,
          },
          <String, dynamic>{
            'name': 'JMComic-0.4.4-release.apk',
            'browser_download_url': 'https://example.com/b.apk',
            'size': 70000000,
          },
        ],
      },
      <String, dynamic>{
        'tag_name': 'v0.5.0-beta',
        'name': 'beta',
        'body': '',
        'html_url': 'https://github.com/x/3',
        'draft': false,
        'prerelease': false,
        'published_at': '2026-11-24T09:00:00Z',
        'assets': <Map<String, dynamic>>[],
      },
      <String, dynamic>{
        'tag_name': 'v0.6.0',
        'name': 'draft only',
        'body': '',
        'html_url': 'https://github.com/x/4',
        'draft': true,
        'prerelease': false,
        'published_at': '2026-11-25T09:00:00Z',
        'assets': <Map<String, dynamic>>[],
      },
    ]);

const String _atomPayload = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.4.3</id>
    <link rel="alternate" type="text/html" href="https://github.com/xzxycx123/JMComic-Flutter-Android/releases/tag/v0.4.3"/>
    <title>JMComic v0.4.3</title>
    <updated>2026-11-22T07:16:12Z</updated>
    <content type="html">&lt;h1&gt;JMComic v0.4.3&lt;/h1&gt;
&lt;p&gt;添加结束页&lt;/p&gt;
&lt;ul&gt;&lt;li&gt;修复首页点赞数&lt;/li&gt;&lt;/ul&gt;</content>
  </entry>
  <entry>
    <id>tag:github.com,2008:Repository/1/v0.4.5</id>
    <link rel="alternate" type="text/html" href="https://github.com/xzxycx123/JMComic-Flutter-Android/releases/tag/v0.4.5"/>
    <title>JMComic v0.4.5</title>
    <updated>2026-11-25T07:16:12Z</updated>
    <content type="html">&lt;h2&gt;修复&lt;/h2&gt;&lt;p&gt;签到日历&lt;/p&gt;</content>
  </entry>
</feed>
''';

const Map<String, List<String>> _plain = <String, List<String>>{
  Headers.contentTypeHeader: <String>['text/plain; charset=utf-8'],
};

void main() {
  group('REST API 路径', () {
    test('解析附件 + 跳过 draft / 预发布，pickNewest 取最高版本', () async {
      final dio = _testDio();
      DioAdapter(dio: dio).onGet(
        RegExp(r'/repos/xzxycx123/JMComic-Flutter-Android/releases$'),
        (server) => server.reply(200, _apiPayload(), headers: _plain),
        queryParameters: <String, dynamic>{'per_page': '30'},
      );
      final client = GithubReleaseClient(dio: dio);
      final releases = await client.fetchReleases();

      expect(releases.map((release) => release.tag).toList(), <String>[
        'v0.3.3.1',
        'v0.4.4',
        'v0.5.0-beta',
      ]);

      final newest = releases.firstWhere((release) => release.tag == 'v0.4.4');
      expect(newest.version, AppVersion.tryParse('0.4.4'));
      expect(newest.apk?.name, 'JMComic-0.4.4-release.apk');
      expect(newest.apk?.downloadUrl, 'https://example.com/b.apk');
      expect(newest.notes.isEmpty, isFalse);
      expect(newest.publishedAt?.toUtc().year, 2026);

      final picked = GithubReleaseClient.pickNewest(
        releases,
        AppVersion.tryParse('0.4.3')!,
      );
      expect(picked?.tag, 'v0.4.4');
      // 预发布不参与「有新版」判断
      expect(
        GithubReleaseClient.pickNewest(
          releases,
          AppVersion.tryParse('0.4.4')!,
        ),
        isNull,
      );
    });

    test('当前已是最新时返回 null', () async {
      final dio = _testDio();
      DioAdapter(dio: dio).onGet(
        RegExp(r'/repos/xzxycx123/JMComic-Flutter-Android/releases$'),
        (server) => server.reply(200, _apiPayload(), headers: _plain),
        queryParameters: <String, dynamic>{'per_page': '30'},
      );
      final client = GithubReleaseClient(dio: dio);
      final newer = await client.fetchNewerThan(
        AppVersion.tryParse('v0.4.4')!,
      );
      expect(newer, isNull);
    });
  });

  group('atom 兜底', () {
    test('API 被限流（403）时改读 releases.atom', () async {
      final dio = _testDio();
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
        RegExp(r'/repos/xzxycx123/JMComic-Flutter-Android/releases$'),
        (server) => server.reply(403, '{"message":"API rate limit exceeded"}', headers: _plain),
        queryParameters: <String, dynamic>{'per_page': '30'},
      );
      adapter.onGet(
        RegExp(r'/releases\.atom$'),
        (server) => server.reply(200, _atomPayload, headers: _plain),
      );

      final client = GithubReleaseClient(dio: dio);
      final releases = await client.fetchReleases();
      expect(releases.map((release) => release.tag).toList(), <String>[
        'v0.4.3',
        'v0.4.5',
      ]);
      expect(releases.first.notes.plainText, contains('添加结束页'));
      expect(releases.first.htmlUrl, contains('/releases/tag/v0.4.3'));
      // atom 拿不到附件信息
      expect(releases.first.apk, isNull);

      final newer = await client.fetchNewerThan(
        AppVersion.tryParse('0.4.3')!,
      );
      expect(newer?.tag, 'v0.4.5');
    });

    test('两路都挂时抛 ReleaseFetchException', () async {
      final dio = _testDio();
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
        RegExp(r'/repos/xzxycx123/JMComic-Flutter-Android/releases$'),
        (server) => server.reply(500, 'boom', headers: _plain),
        queryParameters: <String, dynamic>{'per_page': '30'},
      );
      adapter.onGet(
        RegExp(r'/releases\.atom$'),
        (server) => server.reply(500, 'boom', headers: _plain),
      );
      final client = GithubReleaseClient(dio: dio);
      expect(
        () => client.fetchReleases(),
        throwsA(isA<ReleaseFetchException>()),
      );
    });
  });

  group('assets 面板兜底', () {
    test('从 expanded_assets 的 HTML 里取出 APK 直链', () {
      const html = '<ul>'
          '<li><a href="/xzxycx123/JMComic-Flutter-Android/releases/download/'
          'v0.4.3/JMComic-0.4.3-release.apk" rel="nofollow">JMComic-0.4.3-release.apk</a></li>'
          '<li><a href="/x/y/releases/download/v0.4.3/SHA256SUMS.txt">SHA256SUMS.txt</a></li>'
          '</ul>';
      final asset = GithubReleaseClient.parseAssetsPage(html);
      expect(asset, isNotNull);
      expect(asset!.name, 'JMComic-0.4.3-release.apk');
      expect(
        asset.downloadUrl,
        'https://github.com/xzxycx123/JMComic-Flutter-Android/releases/download/'
        'v0.4.3/JMComic-0.4.3-release.apk',
      );
    });

    test('没有 apk 链接时返回 null', () {
      expect(
        GithubReleaseClient.parseAssetsPage('<ul><li>没有附件</li></ul>'),
        isNull,
      );
    });

    test('atom 结果按 tag 再取一次附件', () async {
      final dio = _testDio();
      final adapter = DioAdapter(dio: dio);
      adapter.onGet(
        RegExp(r'/releases/expanded_assets/v0\.4\.3$'),
        (server) => server.reply(
          200,
          '<a href="/xzxycx123/JMComic-Flutter-Android/releases/download/'
          'v0.4.3/JMComic-0.4.3-release.apk">apk</a>',
          headers: _plain,
        ),
      );
      final client = GithubReleaseClient(dio: dio);
      final releases = GithubReleaseClient.parseAtom(_atomPayload);
      final asset = await client.fetchApkAsset(releases.first);
      expect(asset?.name, 'JMComic-0.4.3-release.apk');
    });
  });

  group('parseAtom', () {
    test('html 正文归一成 block，并解析版本号', () {
      final releases = GithubReleaseClient.parseAtom(_atomPayload);
      expect(releases.length, 2);
      final first = releases.first;
      expect(first.version, AppVersion.tryParse('0.4.3'));
      expect(first.title, 'JMComic v0.4.3');
      expect(
        first.notes.blocks.first.kind.name,
        'heading',
      );
      expect(first.publishedAt?.toUtc().month, 11);
    });

    test('空 feed 得到空列表', () {
      expect(GithubReleaseClient.parseAtom('<feed></feed>'), isEmpty);
    });
  });

  group('ReleaseInfo 展示字段', () {
    test('版本标签与体积文案', () {
      const asset = ReleaseAsset(
        name: 'a.apk',
        downloadUrl: 'https://example.com/a.apk',
        sizeBytes: 68412713,
      );
      expect(asset.sizeText, '65.2 MB');
      final info = ReleaseInfo(
        tag: 'v0.4.4',
        version: AppVersion.tryParse('0.4.4')!,
        title: 't',
        notes: ReleaseNotes.empty,
        htmlUrl: 'https://example.com',
        apk: asset,
        publishedAt: DateTime.utc(2026, 11, 23),
      );
      expect(info.versionLabel, 'v0.4.4');
      expect(info.publishedLabel, isNotEmpty);
      expect(info.toString(), contains('a.apk'));
    });
  });
}
