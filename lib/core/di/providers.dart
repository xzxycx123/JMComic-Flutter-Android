import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/local/download_store.dart';
import '../../data/local/endpoint_store.dart';
import '../../data/local/hive_init.dart';
import '../../data/local/progress_store.dart';
import '../../data/local/settings_store.dart';
import '../../data/repositories/album_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/download_repository.dart';
import '../../data/repositories/home_repository.dart';
import '../../data/repositories/search_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/sources/jm_api_client.dart';
import '../../data/sources/jm_endpoint_resolver.dart';
import '../../data/sources/jm_host_probe.dart';
import '../../data/sources/jm_html_scraper.dart';
import '../../data/models/user_session.dart';
import '../../features/download/engine/notification_service.dart';
import '../../features/download/engine/pdf_sink.dart';
import '../constants/jm_constants.dart';
import '../network/dio_factory.dart';

/// 依赖注入入口：所有跨层对象在这里组装，UI 只 watch provider。
///
/// `main()` 里用 `ProviderScope(overrides: [...])` 注入三个启动期依赖：
/// [sharedPreferencesProvider]、[downloadHistoryProvider]、[cookieJarProvider]。

final Provider<SharedPreferences> sharedPreferencesProvider =
    Provider<SharedPreferences>(
  (ref) => throw StateError('sharedPreferencesProvider 必须在 main() 里 override'),
);

final Provider<DownloadHistory> downloadHistoryProvider =
    Provider<DownloadHistory>(
  (ref) => throw StateError('downloadHistoryProvider 必须在 main() 里 override'),
);

final Provider<JmCookieJar> cookieJarProvider = Provider<JmCookieJar>(
  (ref) => JmCookieJar(),
);

final Provider<EndpointStore> endpointStoreProvider = Provider<EndpointStore>(
  (ref) => EndpointStore(ref.watch(sharedPreferencesProvider)),
);

final Provider<Dio> jmDioProvider = Provider<Dio>((ref) {
  final dio = createJmDio(jar: ref.watch(cookieJarProvider));
  ref.onDispose(dio.close);
  return dio;
});

/// 探测专用 Dio：连接 5s / 收发 8s，避免单台死线路拖垮整轮测速。
final Provider<Dio> jmProbeDioProvider = Provider<Dio>((ref) {
  final dio = createJmDio(
    connectTimeout: const Duration(seconds: 5),
    ioTimeout: const Duration(seconds: 8),
  );
  ref.onDispose(dio.close);
  return dio;
});

final Provider<JmHostProbe> hostProbeProvider = Provider<JmHostProbe>((ref) {
  final appVersion = ref.watch(endpointStoreProvider).appVersion;
  return JmHostProbe(
      dio: ref.watch(jmProbeDioProvider), appVersion: appVersion,);
});

final Provider<JmEndpointResolver> endpointResolverProvider =
    Provider<JmEndpointResolver>(
  (ref) => JmEndpointResolver(
    dio: ref.watch(jmDioProvider),
    store: ref.watch(endpointStoreProvider),
    probe: ref.watch(hostProbeProvider),
  ),
);

final Provider<JmApi> jmApiProvider = Provider<JmApi>(
  (ref) => JmApiClient(
    store: ref.watch(endpointStoreProvider),
    dio: ref.watch(jmDioProvider),
    cookieJar: ref.watch(cookieJarProvider),
    resolver: ref.watch(endpointResolverProvider),
    autoSwitchHost: () => ref.read(settingsProvider).autoSwitchHost,
  ),
);

/// 冷启动引导：域名发现 + /setting（cookie / img_host / appVersion）。
/// 失败时抛错，UI 侧展示可重试的错误态。
final FutureProvider<JmApi> jmBootstrapProvider =
    FutureProvider<JmApi>((ref) async {
  final api = ref.watch(jmApiProvider);
  await api.prepare();
  return api;
});

/// 线路 / 版本 / cookie 状态快照。
final FutureProvider<UserSession> sessionProvider =
    FutureProvider<UserSession>((ref) async {
  final api = await ref.watch(jmBootstrapProvider.future);
  return api.session;
});

// ---------------------------------------------------------------- 本地存储
final Provider<ProgressStore> progressStoreProvider = Provider<ProgressStore>(
  (ref) => ProgressStore(Hive.box<dynamic>(HiveBoxes.readerProgress)),
);

final Provider<SearchHistoryStore> searchHistoryStoreProvider =
    Provider<SearchHistoryStore>(
  (ref) => SearchHistoryStore(Hive.box<dynamic>(HiveBoxes.searchHistory)),
);


// ---------------------------------------------------------------- 仓储
final FutureProvider<HomeRepository> homeRepositoryProvider =
    FutureProvider<HomeRepository>((ref) async {
  final api = await ref.watch(jmBootstrapProvider.future);
  const scraper = JmHtmlScraper();
  final dio = ref.watch(jmDioProvider);
  return HomeRepository(
    api: api,
    cacheBox: Hive.box<dynamic>(HiveBoxes.feedCache),
    // HTML 兜底：API 全挂时依次试 API 域名与发布页网页域名（含国内 comic18j-*）。
    htmlFallback: () async {
      final hosts = <String>{
        api.apiHost,
        ...JmConstants.webHosts,
      }.where((host) => host.isNotEmpty);
      for (final host in hosts) {
        final feed = await scraper.fetch(dio, host);
        if (feed != null) return feed;
      }
      return null;
    },
  );
});

final FutureProvider<CatalogRepository> catalogRepositoryProvider =
    FutureProvider<CatalogRepository>((ref) async {
  final api = await ref.watch(jmBootstrapProvider.future);
  return CatalogRepository(api);
});

final FutureProvider<SearchRepository> searchRepositoryProvider =
    FutureProvider<SearchRepository>((ref) async {
  final api = await ref.watch(jmBootstrapProvider.future);
  return SearchRepository(
    api: api,
    history: ref.watch(searchHistoryStoreProvider),
  );
});

final FutureProvider<AlbumRepository> albumRepositoryProvider =
    FutureProvider<AlbumRepository>((ref) async {
  final api = await ref.watch(jmBootstrapProvider.future);
  return AlbumRepository(
    api: api,
    progress: ref.watch(progressStoreProvider),
  );
});

final Provider<SessionRepository> sessionRepositoryProvider =
    Provider<SessionRepository>(
  (ref) => SessionRepository(
    api: ref.watch(jmApiProvider),
    store: ref.watch(endpointStoreProvider),
    resolver: ref.watch(endpointResolverProvider),
  ),
);

final Provider<PdfSink> pdfSinkProvider =
    Provider<PdfSink>((ref) => FallbackPdfSink());

final Provider<DownloadNotificationService> downloadNotificationProvider =
    Provider<DownloadNotificationService>(
        (ref) => DownloadNotificationService(),);

final Provider<DownloadRepository> downloadRepositoryProvider =
    Provider<DownloadRepository>(
  (ref) => DownloadRepository(
    apiLoader: () => ref.read(jmBootstrapProvider.future),
    history: ref.watch(downloadHistoryProvider),
    sink: ref.watch(pdfSinkProvider),
    notifications: ref.watch(downloadNotificationProvider),
  ),
);
