import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/data/local/endpoint_store.dart';
import 'package:jm_comic/data/models/jm_host_entry.dart';
import 'package:jm_comic/data/sources/jm_endpoint_resolver.dart';
import 'package:jm_comic/data/sources/jm_host_probe.dart';

import '../helpers/test_env.dart';

class _FakeProbe extends JmHostProbe {
  _FakeProbe(this.okHosts) : super(dio: Dio());

  final Map<String, int> okHosts;
  final List<String> probed = <String>[];

  @override
  Future<JmHostProbeResult> probeApi(String host,
      {Duration timeout = JmConstants.probeTimeout,}) async {
    probed.add(host);
    final latency = okHosts[host];
    return JmHostProbeResult(
      host: host,
      kind: JmHostKind.api,
      ok: latency != null,
      status: latency != null ? 'ok' : 'timeout',
      latencyMs: latency ?? 5000,
      imgHost: latency != null ? 'cdn-msp.example.com' : '',
      appVersion: latency != null ? '2.1.13' : '',
    );
  }

  @override
  Future<List<JmHostProbeResult>> probeImages(
    Iterable<String> hosts, {
    int concurrency = 4,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    return <JmHostProbeResult>[
      for (final host in hosts)
        JmHostProbeResult(
          host: host,
          kind: JmHostKind.image,
          ok: true,
          status: 'ok',
          latencyMs: 100,
        ),
    ];
  }
}

String seedJson(String checkedAt) => jsonEncode(<String, dynamic>{
      'schema': 2,
      'generatedAt': checkedAt,
      'api': <Map<String, dynamic>>[
        <String, dynamic>{
          'host': 'seed-a.example.com',
          'status': 'ok',
          'latencyMs': 900,
          'checkedAt': checkedAt,
        },
        <String, dynamic>{
          'host': 'seed-b.example.com',
          'status': 'timeout',
          'latencyMs': 5000,
          'checkedAt': checkedAt,
        },
      ],
      'image': <Map<String, dynamic>>[
        <String, dynamic>{
          'host': 'cdn-seed.example.com',
          'status': 'ok',
          'latencyMs': 800,
        },
      ],
      'web': <Map<String, dynamic>>[
        <String, dynamic>{
          'host': 'comic18j-susu.com',
          'status': 'ok',
          'latencyMs': 700,
          'domestic': true,
        },
      ],
    });

const String _publication = '''
<main>
  <div class="international"><span>18comic.vip</span></div>
  <div class="china"><span>comic18j-susu.com</span></div>
</main>
''';

const String _mirror = '''
    DOMAIN_API_LIST = shuffled(\'\'\'
    mirror.example.com
    \'\'\')
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EndpointStore store;

  setUp(() async {
    await initTestStores();
    final prefs = await testPreferences();
    await prefs.clear();
    store = EndpointStore(prefs);
  });

  /// [checkedAt] 为空表示「种子里是旧数据」，会触发一轮实测。
  JmEndpointResolver buildResolver(_FakeProbe probe, {String? checkedAt}) {
    final seed = seedJson(checkedAt ?? '2000-01-01T00:00:00Z');
    return JmEndpointResolver(
      dio: Dio(),
      store: store,
      probe: probe,
      seedLoader: (path) async =>
          path == JmConstants.hostSeedAsset ? seed : null,
      textLoader: (url) async {
        if (JmConstants.publicationUrls.contains(url)) return _publication;
        if (JmConstants.domainMirrorUrls.contains(url)) return _mirror;
        return null;
      },
    );
  }

  test('种子 + 发布页 + 镜像合并，实测 ok 的线路排第一', () async {
    final probe = _FakeProbe(<String, int>{'seed-b.example.com': 320});
    final report = await buildResolver(probe).refresh(force: true);

    expect(report.sources, containsAll(<String>['seed', 'pub', 'mirror']));
    expect(report.candidates, greaterThanOrEqualTo(4));
    expect(probe.probed, isNotEmpty, reason: '种子是旧数据，必须重测');
    expect(report.apiHosts.first, 'seed-b.example.com');
    expect(store.healthOf('seed-b.example.com')?.ok, isTrue);
    expect(report.imageHosts,
        containsAll(<String>['cdn-msp.example.com', 'comic18j-susu.com']),);
  });

  test('种子里的新鲜结论会先回填：TTL 内不再重复探测', () async {
    final probe = _FakeProbe(<String, int>{});
    final report =
        await buildResolver(probe, checkedAt: DateTime.now().toIso8601String())
            .refresh(force: true);

    expect(probe.probed, isEmpty);
    expect(report.probes, isEmpty);
    expect(report.apiHosts.first, 'seed-a.example.com');
    expect(report.message, contains('沿用'));
  });

  test('3 分钟内的 refresh 复用缓存，不再发起请求', () async {
    final probe = _FakeProbe(<String, int>{});
    final resolver = buildResolver(probe);
    final first = await resolver.refresh(force: true);
    final second = await resolver.refresh();

    expect(identical(first, second), isTrue);
    expect(resolver.lastReport, isNotNull);
  });

  test('probeAll 会跑全部线路并刷新图床表', () async {
    final probe = _FakeProbe(<String, int>{'www.cdnutc.cc': 400});
    final report = await buildResolver(probe).probeAll();

    expect(probe.probed, contains('www.cdnutc.cc'));
    expect(report.apiHosts.first, 'www.cdnutc.cc');
    expect(store.imageHosts.first, 'cdn-msp.example.com');
    expect(store.imageHosts, containsAll(<String>['comic18j-susu.com']));
  });

  test('stripLeadingNonAscii 与 Kotlin 的 dropWhile 语义一致', () {
    expect(
      JmEndpointResolver.stripLeadingNonAscii('禁漫水印{"Server":[]}'),
      '{"Server":[]}',
    );
    expect(
      JmEndpointResolver.stripLeadingNonAscii('   {"Server":[]}   '),
      '{"Server":[]}',
    );
  });
}
