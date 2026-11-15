import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/data/models/jm_host_entry.dart';
import 'package:jm_comic/data/sources/jm_crypto.dart';
import 'package:jm_comic/data/sources/jm_host_probe.dart';

/// 用自定义 HttpClientAdapter 精确区分不同 host（DioAdapter 的路由匹配会忽略 host）。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(String text, int status) => ResponseBody.fromString(
      text,
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>['application/json; charset=utf-8'],
      },
    );

const String _ts = '1700566805';

String _envelope(Map<String, dynamic> setting, {String? ts}) {
  final payload = JmCrypto.encryptPayload(jsonEncode(setting), ts ?? _ts);
  return jsonEncode(<String, dynamic>{'code': 200, 'data': payload});
}

void main() {
  late Dio dio;

  setUp(() {
    dio = Dio(BaseOptions(responseType: ResponseType.plain));
  });

  JmHostProbe probeWith(
      FutureOr<ResponseBody> Function(RequestOptions options) handler,) {
    dio.httpClientAdapter = _StubAdapter(handler);
    return JmHostProbe(dio: dio, timestampProvider: () => _ts);
  }

  group('API 探测', () {
    test('/setting 200 + 可解密 → ok，并带出 img_host / appVersion', () async {
      final probe = probeWith((options) {
        expect(options.uri.host, 'www.cdnutc.cc');
        expect(options.uri.path, '/setting');
        return _json(
          _envelope(<String, dynamic>{
            'jm3_version': '2.1.13',
            'img_host': 'https://cdn-msp.jmdanjonproxy.xyz',
          }),
          200,
        );
      });

      final result = await probe.probeApi('www.cdnutc.cc');
      expect(result.ok, isTrue);
      expect(result.status, 'ok');
      expect(result.kind, JmHostKind.api);
      expect(result.appVersion, '2.1.13');
      expect(result.imgHost, 'cdn-msp.jmdanjonproxy.xyz');
    });

    test('HTTP 403 → http_403（Cloudflare 挡板之类）', () async {
      final probe = probeWith((options) => _json('<html>403</html>', 403));
      final result = await probe.probeApi('www.cdnbtd.cc');
      expect(result.ok, isFalse);
      expect(result.status, 'http_403');
      expect(result.httpStatus, 403);
    });

    test('HTTP 200 但密文解不开 → decrypt_failed（旧 AES-128 实现的典型症状）', () async {
      final probe = probeWith(
        (options) =>
            _json('{"code":200,"data":"AAAAAAAAAAAAAAAAAAAAAA=="}', 200),
      );
      final result = await probe.probeApi('www.cdngwc.net');
      expect(result.ok, isFalse);
      expect(result.status, 'decrypt_failed');
    });

    test('返回 HTML 而不是 JSON → not_json', () async {
      final probe = probeWith((options) => _json('<html>禁漫娘</html>', 200));
      final result = await probe.probeApi('www.cdngwc.club');
      expect(result.status, 'not_json');
    });

    test('code != 200 → code_xxx', () async {
      final probe = probeWith(
        (options) => _json(
            jsonEncode(<String, dynamic>{'code': 400, 'errorMsg': '參數錯誤'}),
            200,),
      );
      final result = await probe.probeApi('www.cdngwc.cc');
      expect(result.status, 'code_400');
      expect(result.detail, '參數錯誤');
    });

    test('并发批量按输入顺序返回', () async {
      final probe = probeWith((options) {
        final host = options.uri.host;
        if (host == 'ok.example.com') {
          return _json(
              _envelope(<String, dynamic>{'jm3_version': '2.1.13'}), 200,);
        }
        return _json('nope', 500);
      });

      final results = await probe.probeApis(
        <String>['ok.example.com', 'bad.example.com', 'timeout.example.com'],
        concurrency: 3,
      );
      expect(results.map((item) => item.host), <String>[
        'ok.example.com',
        'bad.example.com',
        'timeout.example.com',
      ]);
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isFalse);
    });

    test('非法域名不发起请求', () async {
      var called = false;
      final probe = probeWith((options) {
        called = true;
        return _json('{}', 200);
      });
      final result = await probe.probeApi('not a host');
      expect(result.status, 'invalid_host');
      expect(called, isFalse);
    });
  });

  group('图床探测', () {
    test('200 + image/jpeg → ok', () async {
      final probe = probeWith(
        (options) => ResponseBody.fromBytes(
          Uint8List.fromList(List<int>.filled(2048, 7)),
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['image/jpeg'],
          },
        ),
      );
      final result = await probe.probeImage('cdn-msp.jmapiproxy1.cc');
      expect(result.ok, isTrue);
      expect(result.kind, JmHostKind.image);
    });

    test('200 但返回 HTML → not_image', () async {
      final probe = probeWith(
        (options) => ResponseBody.fromString(
          '<html>blocked</html>',
          200,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      );
      final result = await probe.probeImage('cdn.example.com');
      expect(result.ok, isFalse);
      expect(result.status, 'not_image');
    });
  });

  group('网页探测', () {
    test('Cloudflare 挑战页单独标记', () async {
      final probe = probeWith(
        (options) => ResponseBody.fromString(
          '<html><title>Just a moment...</title></html>',
          403,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>['text/html'],
          },
        ),
      );
      final result = await probe.probeWeb('comic18j-susu.com');
      expect(result.status, 'cloudflare_challenge');
    });
  });
}
