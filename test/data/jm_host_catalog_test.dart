import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/jm_host_entry.dart';
import 'package:jm_comic/data/sources/jm_host_catalog.dart';

const String _publicationHtml = '''
<main>
  <div class="international"><span>18comic.vip</span><span>18comic.ink</span></div>
  <div class="southeast_asia"><span>https://jmcomic-zzz.one</span><span>jmcomic-zzz.org</span></div>
  <div class="china"><span>comic18j-susu.com</span></div>
  <div class="first_line"><span>comic18j-nico.work</span></div>
  <div class="second_line"><span>comic18j-neo.com</span></div>
</main>
''';

const String _mirrorConfig = '''
    DOMAIN_API_LIST = shuffled(\'\'\'
    www.cdnhjk.net
    www.cdngwc.cc
    \'\'\')

    DOMAIN_IMAGE_LIST = shuffled(\'\'\'
    cdn-msp.jmapiproxy1.cc
    cdn-msp3.jmapiproxy2.cc
    \'\'\')
''';

void main() {
  group('域名服务', () {
    test('Setting / Server / jm3_Server 三张表都收，标签保留', () {
      const payload = '{"Setting":["www.cdnutc.cc"],'
          '"Server":["www.cdnutc.cc","www.cdngwc.net"],'
          '"jm3_Server":[["www.cdnutc.cc","線路2"],["www.cdntc.me","線路5"]]}';
      final entries = JmHostCatalog.parseDomainServer(payload);
      final hosts = JmHostCatalog.hostsOf(entries, JmHostKind.api);

      expect(
          hosts,
          containsAll(
              <String>['www.cdnutc.cc', 'www.cdngwc.net', 'www.cdntc.me'],),);
      // 去重后只出现一次
      expect(hosts.where((host) => host == 'www.cdnutc.cc').length, 1);

      final labeled =
          entries.firstWhere((entry) => entry.host == 'www.cdnutc.cc');
      expect(labeled.label, '線路2');
      expect(labeled.sources,
          containsAll(<String>['tos:Setting', 'tos:Server', 'tos:jm3_Server']),);
    });

    test('坏 JSON 返回空表而不是抛异常', () {
      expect(JmHostCatalog.parseDomainServer('not json'), isEmpty);
    });
  });

  group('发布页', () {
    test('內地 / 分流 栏标成国内，网页域名带标签', () {
      final entries = JmHostCatalog.parsePublication(_publicationHtml);
      final hosts = JmHostCatalog.hostsOf(entries, JmHostKind.web);

      expect(
        hosts,
        containsAll(<String>[
          '18comic.vip',
          'jmcomic-zzz.one',
          'comic18j-susu.com',
          'comic18j-nico.work',
          'comic18j-neo.com',
        ]),
      );
      final domestic = entries
          .where((entry) => entry.domestic)
          .map((entry) => entry.host)
          .toSet();

      expect(domestic, <String>{
        'comic18j-susu.com',
        'comic18j-nico.work',
        'comic18j-neo.com',
      });
      expect(
          entries
              .firstWhere((entry) => entry.host == 'comic18j-susu.com')
              .label,
          '內地',);
    });
  });

  group('开源镜像配置', () {
    test('DOMAIN_API_LIST / DOMAIN_IMAGE_LIST 分别落到 api / image', () {
      final entries = JmHostCatalog.parseMirrorConfig(_mirrorConfig);
      expect(JmHostCatalog.hostsOf(entries, JmHostKind.api),
          <String>['www.cdnhjk.net', 'www.cdngwc.cc'],);
      expect(
        JmHostCatalog.hostsOf(entries, JmHostKind.image),
        <String>['cdn-msp.jmapiproxy1.cc', 'cdn-msp3.jmapiproxy2.cc'],
      );
    });
  });

  group('打包种子 assets/data/jm_hosts.json', () {
    test('包含实测可用的 API 线路与国内图床', () {
      final file = File('assets/data/jm_hosts.json');
      expect(file.existsSync(), isTrue);

      final entries = JmHostCatalog.parseSeed(file.readAsStringSync());
      final api = JmHostCatalog.hostsOf(entries, JmHostKind.api);
      final image = JmHostCatalog.hostsOf(entries, JmHostKind.image);
      final web = JmHostCatalog.hostsOf(entries, JmHostKind.web);

      expect(api, contains('www.cdnutc.cc'));
      expect(web,
          containsAll(<String>['comic18j-susu.com', 'comic18j-nico.work']),);
      expect(image, contains('comic18j-susu.com'));

      final seed = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(seed['generatedAt'], isNotEmpty);
      expect(seed['api'], isNotEmpty);
    });
  });

  group('合并', () {
    test('同 host 同 kind 合并 sources，ok 状态优先', () {
      final merged = JmHostCatalog.merge(<JmHostEntry>[
        const JmHostEntry(
          host: 'www.cdnutc.cc',
          kind: JmHostKind.api,
          sources: <String>['tos'],
          status: 'timeout',
        ),
        const JmHostEntry(
          host: 'www.cdnutc.cc',
          kind: JmHostKind.api,
          sources: <String>['github'],
          status: 'ok',
          latencyMs: 1200,
          label: '線路2',
        ),
      ]);
      expect(merged.length, 1);
      expect(merged.single.status, 'ok');
      expect(merged.single.latencyMs, 1200);
      expect(merged.single.sources, containsAll(<String>['tos', 'github']));
      expect(merged.single.label, '線路2');
    });
  });
}
