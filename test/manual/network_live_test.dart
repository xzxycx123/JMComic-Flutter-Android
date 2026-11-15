@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/core/network/dio_factory.dart';
import 'package:jm_comic/data/sources/jm_host_probe.dart';

/// 实网联调用例（默认跳过，CI 不跑）。
///
/// ```powershell
/// flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 test/manual/network_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('JM_LIVE');

void main() {
  test(
    '实网：/setting 全链路可用（AES-256 解密 + img_host）',
    () async {
      final dio = createJmDio(
        connectTimeout: const Duration(seconds: 10),
        ioTimeout: const Duration(seconds: 25),
      );
      addTearDown(dio.close);

      final probe = JmHostProbe(dio: dio);
      final results = await probe.probeApis(
        JmConstants.defaultApiHosts.take(4),
        concurrency: 4,
        timeout: const Duration(seconds: 20),
      );

      for (final result in results) {
        // ignore: avoid_print
        print(
            '${result.host.padRight(18)} ${result.status.padRight(12)} ${result.latencyMs}ms img=${result.imgHost}',);
      }

      final ok = results.where((result) => result.ok).toList(growable: false);
      expect(ok, isNotEmpty, reason: '四条内置线路都不可用时先查网络/代理');
      expect(ok.first.appVersion, isNotEmpty);
      expect(
        ok.first.imgHost,
        contains('.'),
      );
    },
    skip: _live ? false : '默认跳过；用 --dart-define=JM_LIVE=true 开启',
  );

  test(
    '实网：国内域名能直出 /media 封面（图床兜底）',
    () async {
      final dio = createJmDio(
        connectTimeout: const Duration(seconds: 10),
        ioTimeout: const Duration(seconds: 25),
      );
      addTearDown(dio.close);

      final probe = JmHostProbe(dio: dio);
      final results = await probe.probeImages(
        JmConstants.domesticHosts,
        concurrency: 3,
        timeout: const Duration(seconds: 20),
      );

      for (final result in results) {
        // ignore: avoid_print
        print(
            '${result.host.padRight(24)} ${result.status.padRight(12)} ${result.latencyMs}ms ${result.detail}',);
      }

      expect(
        results.where((result) => result.ok),
        isNotEmpty,
      );
    },
    skip: _live ? false : '默认跳过；用 --dart-define=JM_LIVE=true 开启',
  );
}
