import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../constants/jm_constants.dart';
import '../utils/logger.dart';

/// 会话级 cookie（对齐 JmScript 的 MemoryCookieJar）。
///
/// `/setting` 下发 5 个 cookie，后续请求必须携带，否则会被重定向到引导页。
class JmCookieJar {
  final Map<String, String> _cookies = <String, String>{};

  int get length => _cookies.length;

  void absorb(Response<dynamic> response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final header in raw) {
      final pair = header.split(';').first.trim();
      final index = pair.indexOf('=');
      if (index <= 0) continue;
      final name = pair.substring(0, index).trim();
      final value = pair.substring(index + 1).trim();
      if (name.isEmpty) continue;
      // 同名的旧 cookie 直接替换（JM 会按域轮换会话 cookie）。
      _cookies.remove(name);
      _cookies[name] = value;
    }
  }

  String? get headerValue {
    if (_cookies.isEmpty) return null;
    return _cookies.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }

  void clear() => _cookies.clear();
}

class _CookieInterceptor extends Interceptor {
  _CookieInterceptor(this.jar);

  final JmCookieJar jar;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final value = jar.headerValue;
    if (value != null && value.isNotEmpty) {
      options.headers['cookie'] = value;
    }
    handler.next(options);
  }

  @override
  void onResponse(
      Response<dynamic> response, ResponseInterceptorHandler handler,) {
    jar.absorb(response);
    handler.next(response);
  }
}

/// Dart 侧只会走 HTTP/1.1（[HttpClient] 不支持 h2），正好绕开 JM CDN 的 h2 preface 故障。
///
/// 代理：`--dart-define=JM_PROXY=http://127.0.0.1:7890`，本机调试 FlClash 时用；
/// 真机走 TUN 模式即可。
///
/// 超时：连接 8s（旧值 15s 会让「首台死线路」单独吃掉十几秒），
/// 收发 30s，业务请求再用 [Options.receiveTimeout] 收紧到单次尝试预算。
Dio createJmDio({
  JmCookieJar? jar,
  String? proxyUrl,
  Duration connectTimeout = const Duration(seconds: 8),
  Duration ioTimeout = const Duration(seconds: 30),
  Duration idleTimeout = const Duration(seconds: 15),
}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: connectTimeout,
      sendTimeout: ioTimeout,
      receiveTimeout: ioTimeout,
      followRedirects: true,
      maxRedirects: 5,
      responseType: ResponseType.plain,
      headers: <String, dynamic>{'User-Agent': JmConstants.userAgent},
    ),
  );

  final effectiveProxy =
      (proxyUrl ?? const String.fromEnvironment('JM_PROXY')).trim();
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient()
        ..idleTimeout = idleTimeout
        ..connectionTimeout = connectTimeout;
      if (effectiveProxy.isNotEmpty) {
        final hostPort = effectiveProxy
            .replaceFirst(RegExp(r'^https?://'), '')
            .replaceAll(RegExp(r'/$'), '');
        client.findProxy = (Uri uri) => 'PROXY $hostPort';
        Log.i('Dio 走代理 $hostPort');
      }
      return client;
    },
  );

  if (jar != null) {
    dio.interceptors.add(_CookieInterceptor(jar));
  }
  return dio;
}
