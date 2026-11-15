import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/core/network/dio_factory.dart';
import 'package:jm_comic/data/local/endpoint_store.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/data/sources/jm_crypto.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

/// 按 host 分流返回的 stub adapter（DioAdapter 的路由匹配会忽略 host，不能用）。
class _HostStubAdapter implements HttpClientAdapter {
  _HostStubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final List<String> visited = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    visited.add(options.uri.host);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

const String _ts = '1700566805';

ResponseBody _json(String text, [int status = 200]) => ResponseBody.fromString(
      text,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
      },
    );

String _envelope(dynamic payload) {
  final data = JmCrypto.encryptPayload(jsonEncode(payload), _ts);
  return jsonEncode(<String, dynamic>{'code': 200, 'data': data});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late _HostStubAdapter adapter;
  late EndpointStore store;
  late JmApiClient client;

  setUp(() async {
    await initTestStores();
    final prefs = await testPreferences();
    await prefs.clear();
    store = EndpointStore(prefs);

    dio = Dio(BaseOptions(responseType: ResponseType.plain));
    adapter = _HostStubAdapter((options) {
      if (options.uri.host == 'dead.example.com') {
        // 能连上但被重定向到引导页：HTTP 200 + HTML
        return _json('<html>禁漫娘</html>');
      }
      return _json(_envelope(Fixtures.promote()));
    });
    dio.httpClientAdapter = adapter;

    client = JmApiClient(
      store: store,
      dio: dio,
      cookieJar: JmCookieJar(),
      timestampProvider: () => _ts,
    );
  });

  test('首台线路返回 HTML 时自动换线，并把成功线路记为 activeHost', () async {
    await store.setManualHost('dead.example.com');

    final modules = await client.fetchPromote();

    expect(modules, isNotEmpty);
    expect(adapter.visited.first, 'dead.example.com');
    expect(client.apiHost, isNot('dead.example.com'));
    expect(store.isCoolingDown('dead.example.com'), isTrue);
    expect(store.healthOf(client.apiHost)?.ok, isTrue);
  });

  test('成功线路会被置顶：下一次请求不再先撞失败线路', () async {
    await store.setManualHost('dead.example.com');
    await client.fetchPromote();
    final working = client.apiHost;

    adapter.visited.clear();
    await client.fetchPromote();

    // 手填线路仍然第一（显式选择），紧随其后就是上次成功的线路。
    expect(adapter.visited.take(2), <String>['dead.example.com', working]);
  });

  test('全部线路失败时抛 JmApiException 并列出尝试过的线路', () async {
    dio.httpClientAdapter =
        _HostStubAdapter((options) => _json('<html>blocked</html>'));

    await expectLater(
      client.fetchPromote(),
      throwsA(
        isA<JmApiException>().having(
          (error) => error.message,
          'message',
          contains('所有 API 线路均连接失败'),
        ),
      ),
    );
    expect(store.apiHealth.where((item) => item.ok), isEmpty);
  });
}
