import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:jm_comic/core/network/api_exception.dart';
import 'package:jm_comic/core/network/dio_factory.dart';
import 'package:jm_comic/data/local/endpoint_store.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';
import 'package:jm_comic/data/sources/jm_crypto.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_env.dart';

const String _ts = '1700566805';

/// mock 适配器会把非 String 的 body 自行 JSON 编码，所以这里直接给 Map。
Map<String, dynamic> _envelope(dynamic payload) => <String, dynamic>{
      'code': 200,
      'data': JmCrypto.encryptPayload(jsonEncode(payload), _ts),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Dio dio;
  late DioAdapter adapter;
  late JmApiClient client;

  setUp(() async {
    await initTestStores();
    final prefs = await testPreferences();
    dio = Dio(
      BaseOptions(
        responseType: ResponseType.plain,
        headers: <String, dynamic>{'User-Agent': 'test'},
      ),
    );
    // UrlRequestMatcher 只比对路由，忽略 host（客户端会按线路表轮换 6 个域名）。
    adapter = DioAdapter(dio: dio, matcher: const UrlRequestMatcher());
    dio.httpClientAdapter = adapter;
    client = JmApiClient(
      store: EndpointStore(prefs),
      dio: dio,
      cookieJar: JmCookieJar(),
      timestampProvider: () => _ts,
    );
  });

  test('promote：解密顶层数组 → 模块', () async {
    adapter.onGet(
      RegExp(r'/promote$'),
      (server) => server.reply(200, _envelope(Fixtures.promote())),
    );

    final modules = await client.fetchPromote();
    expect(modules.length, 2);
    expect(modules.first.items.length, 2);
  });

  test('latest：带 page 参数并解出数组', () async {
    adapter.onGet(
      RegExp(r'/latest$'),
      (server) => server.reply(200, _envelope(Fixtures.latest())),
    );

    final albums = await client.fetchLatest(page: 2);
    expect(albums.length, 4);
    expect(albums.first.id, '1490663');
  });

  test('code != 200 → JmContentException（不轮换线路）', () async {
    adapter.onGet(
      RegExp(r'/promote$'),
      (server) => server.reply(
        200,
        <String, dynamic>{'code': 400, 'errorMsg': '參數錯誤'},
      ),
    );

    expect(
      () => client.fetchPromote(),
      throwsA(
        isA<JmContentException>().having((error) => error.message, 'message', contains('參數錯誤')),
      ),
    );
  });

  test('响应不是 JSON → JmApiException（走完所有线路）', () async {
    adapter.onGet(
      RegExp(r'/promote$'),
      (server) => server.reply(200, '<html>禁漫娘</html>'),
    );

    expect(
      () => client.fetchPromote(),
      throwsA(isA<JmApiException>()),
    );
  });

  test('coverUrl / photoUrl 按 §5.6 拼接', () {
    expect(
      client.coverUrl('350234'),
      endsWith('/media/albums/350234_3x4.jpg'),
    );
    expect(
      client.photoUrl('350234', '00001.webp'),
      endsWith('/media/photos/350234/00001.webp'),
    );
  });
}
