// 签到端点探针（只读）：验证 `GET /daily` 结构能被 JmDailyState 解析，并确认
// `POST /daily_chk` 端点存在。未登录时 daily_chk 只回 200 + 空 data，签到是否真正
// 生效必须在手机 App 里登录后跑一次。
//
// 用法：
//   dart run tool/probe_daily.dart [userId]
// 需要代理时先设 HTTPS_PROXY（如 http://127.0.0.1:7890），脚本会交给 dio 用。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/data/models/jm_daily.dart';
import 'package:jm_comic/data/sources/jm_crypto.dart';

String? extractJsonObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end < start) return null;
  return text.substring(start, end + 1);
}

String stamp() => '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';

Dio buildDio() {
  final proxy = Platform.environment['HTTPS_PROXY'] ??
      Platform.environment['HTTP_PROXY'] ??
      '';
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      responseType: ResponseType.plain,
    ),
  );
  if (proxy.isNotEmpty) {
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () => HttpClient()
        ..findProxy =
            ((_) => 'PROXY ${proxy.replaceFirst(RegExp(r'^https?://'), '')}'),
    );
  }
  return dio;
}

Future<Map<String, dynamic>?> call(
  Dio dio,
  String host,
  String path, {
  Map<String, String>? query,
  Map<String, String>? form,
}) async {
  final ts = stamp();
  final response = await dio.request<String>(
    'https://$host$path',
    data: form == null ? null : FormData.fromMap(form),
    queryParameters: query,
    options: Options(
      method: form == null ? 'GET' : 'POST',
      headers: <String, dynamic>{
        'User-Agent': JmConstants.userAgent,
        'token': JmCrypto.buildToken(ts),
        'tokenparam': '$ts,${JmConstants.fallbackAppVersion}',
      },
    ),
  );
  final text = response.data ?? '';
  final jsonText = extractJsonObject(text);
  if (jsonText == null) {
    stdout.writeln(
      '  $path -> 非 JSON：${text.substring(0, text.length.clamp(0, 120))}',
    );
    return null;
  }
  final envelope = jsonDecode(jsonText) as Map<String, dynamic>;
  final rawData = envelope['data'];
  final data = rawData is String ? rawData : '';
  final plain = data.isEmpty
      ? null
      : jsonDecode(JmCrypto.decryptPayload(data, ts)) as Map<String, dynamic>;
  stdout.writeln(
    '  $path -> code=${envelope['code']} '
    'errorMsg=${envelope['errorMsg'] ?? envelope['msg'] ?? ''} '
    'dataType=${rawData.runtimeType} '
    'data=${plain == null ? '<empty>' : '<decoded>'}',
  );
  return plain;
}

Future<void> main(List<String> args) async {
  final userId = args.isEmpty ? '1' : args.first;
  final dio = buildDio();
  for (final host in JmConstants.defaultApiHosts) {
    stdout.writeln('== host $host');
    try {
      final daily = await call(
        dio,
        host,
        JmConstants.dailyPath,
        query: <String, String>{'user_id': userId},
      );
      if (daily == null) continue;
      final state = JmDailyState.fromJson(daily);
      stdout.writeln('  daily_id=${state.dailyId} 行数=${state.rows.length} '
          '本月已签=${state.signedDays} 奖励日=${state.bonusDays} '
          '补签=${state.makeupUsed}/${state.makeupLimit} 活动=${state.eventName}');
      await call(
        dio,
        host,
        JmConstants.dailyCheckInPath,
        form: <String, String>{
          'user_id': userId,
          'daily_id': '${state.dailyId}',
        },
      );
      await call(dio, host, '/zzz_not_exist');
      return;
    } catch (error) {
      stderr.writeln('  host $host 失败：$error');
    }
  }
  stderr.writeln('所有线路都没拿到 /daily');
  exitCode = 1;
}
