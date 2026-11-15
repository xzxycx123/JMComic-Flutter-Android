import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/local/endpoint_store.dart';
import 'package:jm_comic/data/models/jm_host_entry.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EndpointStore store;

  setUp(() async {
    await initTestStores();
    final prefs = await testPreferences();
    await prefs.clear();
    store = EndpointStore(prefs);
  });

  test('没有健康记录时按内置顺序返回，手填线路永远第一', () async {
    await store.setManualHost('manual.example.com');
    final hosts = store.apiHosts;
    expect(hosts.first, 'manual.example.com');
    expect(hosts, containsAll(<String>['www.cdnutc.cc', 'www.cdngwc.net']));
    expect(hosts.length, store.apiHosts.toSet().length, reason: '线路表必须去重');
  });

  test('实测 ok 的线路按延迟升序排到前面', () async {
    await store.recordHealth('www.cdnbtd.cc', JmHostKind.api,
        ok: true, latencyMs: 900,);
    await store.recordHealth('www.cdngwc.net', JmHostKind.api,
        ok: true, latencyMs: 200,);

    final hosts = store.apiHosts;
    expect(hosts.take(2), <String>['www.cdngwc.net', 'www.cdnbtd.cc']);
    expect(store.healthOf('www.cdngwc.net')?.ok, isTrue);
    expect(store.hasFreshHealth('www.cdngwc.net'), isTrue);
  });

  test('失败线路进冷却窗口并排到最后，但手填线路仍然钉在最前', () async {
    await store.setManualHost('manual.example.com');
    await store.recordHealth('manual.example.com', JmHostKind.api,
        ok: false, latencyMs: 5000, status: 'timeout',);
    await store.recordHealth('www.cdngwc.net', JmHostKind.api,
        ok: false, latencyMs: 5000, status: 'timeout',);

    expect(store.isCoolingDown('manual.example.com'), isTrue);
    expect(store.isCoolingDown('www.cdngwc.net'), isTrue);

    final hosts = store.apiHosts;
    expect(hosts.first, 'manual.example.com', reason: '手填线路是显式选择，永远排第一');
    expect(hosts.last, 'www.cdngwc.net', reason: '自动线路失败后进冷却，排到最后');
    expect(store.healthOf('www.cdngwc.net')?.status, 'timeout');
  });

  test('失败后再次成功会清零 failCount 并解除冷却', () async {
    await store.recordHealth('www.cdnutc.cc', JmHostKind.api,
        ok: false, latencyMs: 0, status: 'timeout',);
    expect(store.healthOf('www.cdnutc.cc')?.failCount, 1);

    await store.recordHealth('www.cdnutc.cc', JmHostKind.api,
        ok: true, latencyMs: 780,);
    final health = store.healthOf('www.cdnutc.cc');
    expect(health?.failCount, 0);
    expect(health?.ok, isTrue);
    expect(store.isCoolingDown('www.cdnutc.cc'), isFalse);
  });

  test('图床表包含国内兜底域名', () {
    final hosts = store.imageHosts;
    expect(
        hosts,
        containsAll(<String>[
          'comic18j-susu.com',
          'comic18j-nico.work',
          'comic18j-neo.com',
        ]),);
  });

  test('setImageHosts 把新图床置顶并去重', () async {
    await store.setImageHosts(<String>['cdn-msp.jmdanjonproxy.xyz']);
    await store.setImageHosts(<String>['cdn-msp.jmdanjonproxy.xyz']);
    final hosts = store.imageHosts;
    expect(hosts.first, 'cdn-msp.jmdanjonproxy.xyz');
    expect(
        hosts.where((host) => host == 'cdn-msp.jmdanjonproxy.xyz').length, 1,);
  });

  test('resetHealth / clearDiscovered 清空健康与线路', () async {
    await store.recordHealth('www.cdnutc.cc', JmHostKind.api,
        ok: true, latencyMs: 100,);
    await store.applyDiscoveredHosts(<String>['www.cdnutc.cc']);
    expect(store.apiHealth, isNotEmpty);

    await store.resetHealth();
    expect(store.apiHealth, isEmpty);

    await store.clearDiscovered();
    expect(store.apiHosts, JmHostConstantsFallback.defaults);
  });
}

/// 用常量做断言时避免在测试里重复写死列表。
abstract final class JmHostConstantsFallback {
  static const List<String> defaults = <String>[
    'www.cdnutc.cc',
    'www.cdngwc.net',
    'www.cdngwc.cc',
    'www.cdngwc.club',
    'www.cdnbtd.cc',
    'www.cdnhjk.net',
    'www.cdnutc.me',
  ];
}
