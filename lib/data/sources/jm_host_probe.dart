import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/host_normalizer.dart';
import '../../core/utils/logger.dart';
import '../models/jm_host_entry.dart';
import '../models/json_field.dart';
import 'jm_crypto.dart';

/// 单台主机的连通性结论。
class JmHostProbeResult {
  const JmHostProbeResult({
    required this.host,
    required this.kind,
    required this.ok,
    required this.status,
    required this.latencyMs,
    this.httpStatus = 0,
    this.imgHost = '',
    this.appVersion = '',
    this.detail = '',
  });

  final String host;
  final JmHostKind kind;

  /// 只有「HTTP 200 + code=200 + 能解密 + 关键字段存在」才算 true。
  final bool ok;
  final String status;
  final int latencyMs;
  final int httpStatus;

  /// `/setting.img_host`（探测顺带拿到的当前图床）。
  final String imgHost;
  final String appVersion;
  final String detail;

  bool get isApiOk => kind == JmHostKind.api && ok;

  @override
  String toString() => '$host ${ok ? 'ok' : status} ${latencyMs}ms';
}

/// 真正的连通性探测：不再「通了 TCP 就算能用」，而是跑完整业务链路。
///
/// API：`GET /setting` + `token`/`tokenparam` 头 + AES-256 解密 + `jm3_version`/`img_host` 校验；
/// 图床：`GET /media/albums/<id>_3x4.jpg`，必须 200 且 `content-type: image/*`；
/// 网页：`GET /`，必须 200 且是 HTML（Cloudflare 挑战单独标记）。
class JmHostProbe {
  JmHostProbe({
    required Dio dio,
    this.appVersion = JmConstants.fallbackAppVersion,
    String Function()? timestampProvider,
  })  : _dio = dio,
        _timestampProvider = timestampProvider;

  final Dio _dio;
  final String appVersion;
  final String Function()? _timestampProvider;

  String _timestamp() =>
      _timestampProvider?.call() ??
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();

  // ---------------------------------------------------------------- API
  Future<JmHostProbeResult> probeApi(
    String host, {
    Duration timeout = JmConstants.probeTimeout,
  }) async {
    final normalized = normalizeHost(host);
    if (normalized == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'invalid_host',
        latencyMs: 0,
      );
    }

    final ts = _timestamp();
    final sw = Stopwatch()..start();
    try {
      final response = await _dio.get<String>(
        'https://$normalized${JmConstants.probeSettingPath}',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (code) => code != null && code < 500,
          headers: <String, dynamic>{
            'User-Agent': JmConstants.userAgent,
            'token': JmCrypto.buildToken(ts),
            'tokenparam': '$ts,$appVersion',
          },
        ),
      );
      sw.stop();
      return _decodeSetting(normalized, ts, response, sw.elapsedMilliseconds);
    } catch (error) {
      sw.stop();
      final classified = _classify(error);
      Log.w('API 探测 $normalized 失败：${classified.status} ${classified.detail}');
      return JmHostProbeResult(
        host: normalized,
        kind: JmHostKind.api,
        ok: false,
        status: classified.status,
        latencyMs: sw.elapsedMilliseconds,
        httpStatus: classified.httpStatus,
        detail: classified.detail,
      );
    }
  }

  JmHostProbeResult _decodeSetting(
    String host,
    String ts,
    Response<String> response,
    int latencyMs,
  ) {
    final httpStatus = response.statusCode ?? 0;
    if (httpStatus != 200) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'http_$httpStatus',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
        detail: 'HTTP $httpStatus',
      );
    }

    final text = response.data ?? '';
    final jsonText = _extractJsonObject(text);
    if (jsonText == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'not_json',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
        detail: _preview(text),
      );
    }

    Map<String, dynamic>? envelope;
    try {
      envelope = asMap(jsonDecode(jsonText));
    } catch (_) {
      envelope = null;
    }
    if (envelope == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'not_json',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
      );
    }

    final code = asInt(envelope['code'], 200);
    if (code != 200) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'code_$code',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
        detail:
            asStringOr(envelope['errorMsg'] ?? envelope['msg'], 'code=$code'),
      );
    }

    final data = asString(envelope['data']) ?? '';
    if (data.isEmpty) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'empty_data',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
      );
    }

    Map<String, dynamic>? setting;
    try {
      setting = asMap(jsonDecode(JmCrypto.decryptPayload(data, ts)));
    } catch (error) {
      // 解密失败 = 协议不匹配（历史版本曾把 key 截断成 16 字节，就是死在这里）。
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'decrypt_failed',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
        detail: '$error',
      );
    }
    if (setting == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'payload_unexpected',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
      );
    }

    final version = (asString(setting['jm3_version']) ?? '').trim();
    final imgHost = normalizeHost(asString(setting['img_host']) ?? '') ?? '';
    if (version.isEmpty && imgHost.isEmpty) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.api,
        ok: false,
        status: 'payload_unexpected',
        latencyMs: latencyMs,
        httpStatus: httpStatus,
        detail: _preview(setting.toString()),
      );
    }

    return JmHostProbeResult(
      host: host,
      kind: JmHostKind.api,
      ok: true,
      status: 'ok',
      latencyMs: latencyMs,
      httpStatus: httpStatus,
      imgHost: imgHost,
      appVersion: version,
    );
  }

  // ---------------------------------------------------------------- 图床
  Future<JmHostProbeResult> probeImage(
    String host, {
    String albumId = JmConstants.probeAlbumId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final normalized = normalizeHost(host);
    if (normalized == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.image,
        ok: false,
        status: 'invalid_host',
        latencyMs: 0,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final response = await _dio.get<List<int>>(
        'https://$normalized/media/albums/${albumId}_3x4.jpg',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (code) => code != null && code < 500,
          headers: <String, dynamic>{
            'User-Agent': JmConstants.userAgent,
            'Accept': JmConstants.imageAccept,
            'X-Requested-With': JmConstants.requestedWith,
          },
        ),
      );
      sw.stop();
      final httpStatus = response.statusCode ?? 0;
      final contentType =
          (response.headers.value('content-type') ?? '').toLowerCase();
      final bytes = response.data;
      if (httpStatus != 200) {
        return JmHostProbeResult(
          host: normalized,
          kind: JmHostKind.image,
          ok: false,
          status: 'http_$httpStatus',
          latencyMs: sw.elapsedMilliseconds,
          httpStatus: httpStatus,
        );
      }
      if (contentType.contains('text/html') ||
          contentType.contains('application/json')) {
        return JmHostProbeResult(
          host: normalized,
          kind: JmHostKind.image,
          ok: false,
          status: 'not_image',
          latencyMs: sw.elapsedMilliseconds,
          httpStatus: httpStatus,
          detail: contentType,
        );
      }
      if (bytes == null || bytes.isEmpty) {
        return JmHostProbeResult(
          host: normalized,
          kind: JmHostKind.image,
          ok: false,
          status: 'empty_body',
          latencyMs: sw.elapsedMilliseconds,
          httpStatus: httpStatus,
        );
      }
      return JmHostProbeResult(
        host: normalized,
        kind: JmHostKind.image,
        ok: true,
        status: 'ok',
        latencyMs: sw.elapsedMilliseconds,
        httpStatus: httpStatus,
        detail: '${(bytes.length / 1024).round()}KB',
      );
    } catch (error) {
      sw.stop();
      final classified = _classify(error);
      Log.w('图床探测 $normalized 失败：${classified.status} ${classified.detail}');
      return JmHostProbeResult(
        host: normalized,
        kind: JmHostKind.image,
        ok: false,
        status: classified.status,
        latencyMs: sw.elapsedMilliseconds,
        httpStatus: classified.httpStatus,
        detail: classified.detail,
      );
    }
  }

  // ---------------------------------------------------------------- 网页
  Future<JmHostProbeResult> probeWeb(
    String host, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final normalized = normalizeHost(host);
    if (normalized == null) {
      return JmHostProbeResult(
        host: host,
        kind: JmHostKind.web,
        ok: false,
        status: 'invalid_host',
        latencyMs: 0,
      );
    }

    final sw = Stopwatch()..start();
    try {
      final response = await _dio.get<String>(
        'https://$normalized/',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          validateStatus: (code) => code != null && code < 600,
          headers: <String, dynamic>{
            'User-Agent': JmConstants.userAgent,
            'Accept': 'text/html,application/xhtml+xml',
          },
        ),
      );
      sw.stop();
      final httpStatus = response.statusCode ?? 0;
      final text = response.data ?? '';
      final challenge = text.contains('Just a moment') ||
          text.contains('challenge-platform') ||
          text.contains('cf-chl');
      if (httpStatus == 200 && !challenge && text.contains('<html')) {
        return JmHostProbeResult(
          host: normalized,
          kind: JmHostKind.web,
          ok: true,
          status: 'ok',
          latencyMs: sw.elapsedMilliseconds,
          httpStatus: httpStatus,
        );
      }
      return JmHostProbeResult(
        host: normalized,
        kind: JmHostKind.web,
        ok: false,
        status: challenge ? 'cloudflare_challenge' : 'http_$httpStatus',
        latencyMs: sw.elapsedMilliseconds,
        httpStatus: httpStatus,
      );
    } catch (error) {
      sw.stop();
      final classified = _classify(error);
      return JmHostProbeResult(
        host: normalized,
        kind: JmHostKind.web,
        ok: false,
        status: classified.status,
        latencyMs: sw.elapsedMilliseconds,
        httpStatus: classified.httpStatus,
        detail: classified.detail,
      );
    }
  }

  // ---------------------------------------------------------------- 批量
  /// 并发探测 API 线路：`concurrency` 个 worker 抢队列，按输入顺序返回。
  Future<List<JmHostProbeResult>> probeApis(
    Iterable<String> hosts, {
    int concurrency = 4,
    Duration timeout = JmConstants.probeTimeout,
  }) async {
    final queue = hosts.toList(growable: false);
    if (queue.isEmpty) return const <JmHostProbeResult>[];
    final results = List<JmHostProbeResult?>.filled(queue.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= queue.length) return;
        results[index] = await probeApi(queue[index], timeout: timeout);
      }
    }

    final workers = math.min(concurrency <= 0 ? 1 : concurrency, queue.length);
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
    return results.whereType<JmHostProbeResult>().toList(growable: false);
  }

  /// 批量探测图床。
  Future<List<JmHostProbeResult>> probeImages(
    Iterable<String> hosts, {
    int concurrency = 4,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final queue = hosts.toList(growable: false);
    if (queue.isEmpty) return const <JmHostProbeResult>[];
    final results = List<JmHostProbeResult?>.filled(queue.length, null);
    var cursor = 0;

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= queue.length) return;
        results[index] = await probeImage(queue[index], timeout: timeout);
      }
    }

    final workers = math.min(concurrency <= 0 ? 1 : concurrency, queue.length);
    await Future.wait(List<Future<void>>.generate(workers, (_) => worker()));
    return results.whereType<JmHostProbeResult>().toList(growable: false);
  }

  // ---------------------------------------------------------------- 工具
  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) return null;
    return text.substring(start, end + 1);
  }

  static String _preview(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 80 ? flat : '${flat.substring(0, 80)}…';
  }

  static ({String status, int httpStatus, String detail}) _classify(
      Object error,) {
    if (error is DioException) {
      final response = error.response;
      final httpStatus = response?.statusCode ?? 0;
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return (status: 'timeout', httpStatus: httpStatus, detail: '连接超时');
        case DioExceptionType.badCertificate:
          return (
            status: 'tls_error',
            httpStatus: httpStatus,
            detail: '证书校验失败'
          );
        case DioExceptionType.badResponse:
          return (
            status: 'http_$httpStatus',
            httpStatus: httpStatus,
            detail: 'HTTP $httpStatus'
          );
        case DioExceptionType.cancel:
          return (status: 'cancelled', httpStatus: httpStatus, detail: '已取消');
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
        default:
          break;
      }
      final message = '${error.message ?? ''} ${error.error ?? ''}';
      final lower = message.toLowerCase();
      if (lower.contains('handshake') ||
          lower.contains('certificate') ||
          lower.contains('tls')) {
        return (
          status: 'tls_error',
          httpStatus: httpStatus,
          detail: message.trim()
        );
      }
      if (lower.contains('timeout') || lower.contains('timed out')) {
        return (
          status: 'timeout',
          httpStatus: httpStatus,
          detail: message.trim()
        );
      }
      return (status: 'error', httpStatus: httpStatus, detail: message.trim());
    }
    return (status: 'error', httpStatus: 0, detail: '$error');
  }
}
