@Tags(<String>['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:jm_comic/core/constants/jm_constants.dart';
import 'package:jm_comic/core/network/dio_factory.dart';
import 'package:jm_comic/data/local/endpoint_store.dart';
import 'package:jm_comic/data/sources/jm_api_client.dart';

import '../helpers/test_env.dart';

/// 实网对比用例：首页卡片拿到的点赞量 vs 详情页（`/album.likes`）是否一致。
///
/// 首页/搜索/收藏的卡片现在都走 [JmApi.fetchAlbumLikes]（JmAPI `/album`），
/// 详情页走 [JmApi.getAlbum]（同一个 `likes` 字段）—— 本用例就是拿真实服务端
/// 验证两条路径给出的数字完全相同，并覆盖上千/上万的大数（网页压缩写法
/// `21K`、`1.2万` 会丢精度，这正是 0.4.2「首页点赞量显示不正确」的根因）。
///
/// ```powershell
/// flutter test --dart-define=JM_LIVE=true --dart-define=JM_PROXY=http://127.0.0.1:7890 `
///   test/manual/likes_live_test.dart
/// ```
const bool _live = bool.fromEnvironment('JM_LIVE');
const String _apiHost = String.fromEnvironment(
  'JM_API_HOST',
  defaultValue: 'www.cdnutc.cc',
);

void main() {
  test(
    '实网：首页点赞量与详情页 /album.likes 完全一致',
    () async {
      await initTestStores();
      final prefs = await testPreferences();
      final store = EndpointStore(prefs);
      final dio = createJmDio(
        proxyUrl: const String.fromEnvironment('JM_PROXY'),
        connectTimeout: const Duration(seconds: 12),
        ioTimeout: const Duration(seconds: 30),
      );
      addTearDown(dio.close);

      final api = JmApiClient(
        store: store,
        dio: dio,
        cookieJar: JmCookieJar(),
        // 本机代理偶尔握手抖动：不轮换线路，靠用例自身的重试兜住。
        autoSwitchHost: () => false,
        // 慢线路上单次 /album 可能要 10s+，放宽尝试预算，避免用例被超时打断。
        attemptTimeout: const Duration(seconds: 40),
      );
      // switchApiHost 会打一次 /setting（拿 cookie + 版本），失败就直接跳过。
      final ready = await api.switchApiHost(_apiHost);
      expect(ready, isTrue, reason: '/setting 不通：先查代理 / 线路');

      // 两个排序各取前几本：最新更新大多是 0~几十，人气榜能覆盖上千/上万。
      final ids = <String>[];
      for (final order in <AlbumOrder>[
        AlbumOrder.latestUpdate,
        AlbumOrder.mostViewed,
      ]) {
        final page = await _retry(
          () => api.fetchFilter(page: 1, order: order),
        );
        ids.addAll(
          page.content.take(4).map((album) => album.id),
        );
      }
      expect(ids, isNotEmpty, reason: '列表接口没有返回本子');

      var compared = 0;
      for (final id in ids) {
        int homeLikes;
        int detailLikes;
        try {
          homeLikes = await _retry(() => api.fetchAlbumLikes(id));
          detailLikes = await _retry(
            () async => (await api.getAlbum(id)).likes,
          );
        } catch (error) {
          // 本机代理偶尔整条线路握手失败：跳过这一本，不把网络噪声算成数据不一致。
          // ignore: avoid_print
          print('JM$id 跳过（网络抖动）：$error');
          continue;
        }
        // ignore: avoid_print
        print(
          'JM$id  首页(JmAPI /album.likes)=$homeLikes  详情页(getAlbum.likes)=$detailLikes  '
          '${homeLikes == detailLikes ? 'ok' : 'DIFF'}',
        );
        expect(
          homeLikes,
          detailLikes,
          reason: 'JM$id 的首页点赞量与详情页不一致',
        );
        compared++;
      }
      // ignore: avoid_print
      print('对比 $compared 本，全部一致');
      // 至少 4 本构成有效样本，避免网络全挂时「零对比」也算通过。
      expect(compared, greaterThanOrEqualTo(4));
    },
    skip: _live ? false : '默认跳过；用 --dart-define=JM_LIVE=true 开启',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

/// 代理偶发 TLS 抖动：单次请求失败时退避重试，避免用例被网络噪声打断。
Future<T> _retry<T>(Future<T> Function() run, {int attempts = 4}) async {
  Object? lastError;
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await run();
    } catch (error) {
      lastError = error;
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
  }
  throw lastError!;
}
