import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/dio_factory.dart';
import '../../core/utils/logger.dart';
import '../local/endpoint_store.dart';
import '../models/jm_album_detail.dart';
import '../models/jm_album_summary.dart';
import '../models/jm_category.dart';
import '../models/jm_chapter.dart';
import '../models/jm_favorite_list.dart';
import '../models/jm_host_entry.dart';
import '../models/jm_promote_module.dart';
import '../models/jm_search_page.dart';
import '../models/json_field.dart';
import '../models/user_session.dart';
import 'jm_crypto.dart';
import 'jm_endpoint_resolver.dart';
import 'jm_host_probe.dart';
import 'jm_response_parser.dart';

/// 协议客户端契约：下载引擎只依赖它，便于单测注入 fake。
abstract class JmApi {
  String get apiHost;
  String get imageHost;
  UserSession get session;
  Map<String, String> get imageHeaders;

  /// 可选分流列表（按健康度排序；第一条是当前默认线路）。
  List<String> get availableHosts;

  /// 显式切换分流：拉该线路的 `/setting` 并更新图床/版本；失败返回 false 且保留原线路。
  Future<bool> switchApiHost(String host);

  Future<void> prepare();

  Future<List<JmPromoteModule>> fetchPromote();

  Future<List<JmAlbumSummary>> fetchLatest({int page = 1});

  Future<List<JmCategory>> fetchCategories();

  Future<JmSearchPage> fetchFilter({
    int page = 1,
    String category = '0',
    AlbumOrder order = AlbumOrder.latestUpdate,
  });

  Future<JmSearchPage> search({
    required String query,
    int page = 1,
    AlbumOrder order = AlbumOrder.latestUpdate,
  });

  Future<JmAlbumDetail> getAlbum(String albumId);

  Future<JmChapter> getChapter(JmChapterRef reference);

  Future<int> getScrambleId(String photoId);

  Future<Uint8List> downloadImage(String photoId, String filename);

  String coverUrl(String albumId);

  String photoUrl(String photoId, String filename);

  // ---------------------------------------------------------------- 账号 / 收藏（0.2.0）
  /// `POST /login`（multipart），返回解密后的账号信息；带 `s` 时自动补 AVS cookie。
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  });

  /// `GET /favorite?page&o&folder_id`。
  Future<JmFavoriteList> fetchFavorites({
    int page = 1,
    String order = 'mr',
    int folderId = 0,
  });

  /// `POST /favorite {aid}`：**toggle**，返回 `add` / `remove`。
  Future<String> toggleFavorite(String albumId);

  /// 用收藏列表探一次会话是否还有效（true=有效，false=未登录/失效；网络错误会抛出）。
  Future<bool> pingFavorite();

  Future<void> setCookie(String name, String value);

  Map<String, String> get cookieSnapshot;

  void restoreCookies(Map<String, String> cookies);
}

/// 协议客户端（移植 `JmScript/data/JmApiClient.kt` + 首页端点扩展）。
class JmApiClient implements JmApi {
  JmApiClient({
    required EndpointStore store,
    required Dio dio,
    JmCookieJar? cookieJar,
    JmEndpointResolver? resolver,
    bool Function()? autoSwitchHost,
    this.timestampProvider,
  })  : _store = store,
        _dio = dio,
        _jar = cookieJar ?? JmCookieJar(),
        _autoSwitchHost = autoSwitchHost ?? (() => true),
        _resolver = resolver ??
            JmEndpointResolver(
              dio: dio,
              store: store,
              probe: JmHostProbe(dio: dio, appVersion: store.appVersion),
            );

  final EndpointStore _store;
  final Dio _dio;
  final JmCookieJar _jar;
  final JmEndpointResolver _resolver;

  /// 「自动切换线路」开关（设置页）：关掉后只试首条线路，不再轮换。
  final bool Function() _autoSwitchHost;

  /// 单测注入固定时间戳（服务端响应要用同一 ts 解密）。
  final String Function()? timestampProvider;

  String _activeHost = '';
  String _activeImageHost = '';
  bool _prepared = false;

  @override
  String get apiHost {
    if (_activeHost.isNotEmpty) return _activeHost;
    final hosts = _store.apiHosts;
    return hosts.isEmpty ? '' : hosts.first;
  }

  @override
  String get imageHost {
    if (_activeImageHost.isNotEmpty) return _activeImageHost;
    final hosts = _store.imageHosts;
    return hosts.isEmpty ? '' : hosts.first;
  }

  @override
  Map<String, String> get imageHeaders => <String, String>{
        'User-Agent': JmConstants.userAgent,
        'Referer': 'https://$apiHost/',
        'Accept': JmConstants.imageAccept,
        'X-Requested-With': JmConstants.requestedWith,
      };

  @override
  UserSession get session => _store.toSession(
        apiHost: apiHost,
        imageHost: imageHost,
        cookieCount: _jar.length,
        ready: _prepared,
      );

  // ---------------------------------------------------------------- 引导
  @override
  Future<void> prepare() async {
    // 发现 + 实测（首次冷启动最多 2 批 × 5s；之后 3 分钟内直接复用报告）。
    final report = await _resolver.refresh();
    if (_store.apiHosts.isEmpty) {
      throw JmApiException('没有可用 API 线路：${report.message}', network: true);
    }

    final decoded = await _requestApi('/setting');
    await _applySetting(decoded);
    _prepared = true;
    Log.i(
      'prepare 完成：api=$apiHost img=$imageHost appVersion=${_store.appVersion} cookies=${_jar.length}',
    );
  }

  /// `/setting` 的公共处理：img_host 置顶、版本号升级。
  Future<void> _applySetting(dynamic decoded) async {
    final map = asMap(decoded);
    if (map == null) return;
    final imgHost =
        JmEndpointResolver.normalizeHost(asString(map['img_host']) ?? '');
    if (imgHost != null && imgHost.isNotEmpty) {
      await _store.setImageHosts(<String>[imgHost]);
      _activeImageHost = imgHost;
    }
    final version = asString(map['jm3_version']);
    if (version != null && version.trim().isNotEmpty) {
      await _store.setAppVersion(version);
    }
  }

  // ---------------------------------------------------------------- 分流
  @override
  List<String> get availableHosts => _store.apiHosts;

  @override
  Future<bool> switchApiHost(String host) async {
    final normalized = JmEndpointResolver.normalizeHost(host);
    if (normalized == null) return false;
    final sw = Stopwatch()..start();
    try {
      // 只试目标线路：不轮换、不重试，失败就让 UI 明确提示。
      final decoded = await _requestApiOnHost(
        normalized,
        JmConstants.probeSettingPath,
        tokenSecret: JmConstants.tokenSecret,
      );
      await _applySetting(decoded);
      _activeHost = normalized;
      _prepared = true;
      await _store.markApiHostWorking(normalized);
      await _store.recordHealth(
        normalized,
        JmHostKind.api,
        ok: true,
        latencyMs: sw.elapsedMilliseconds,
        status: 'ok',
      );
      Log.i('分流已切到 $normalized（img=$_activeImageHost）');
      return true;
    } catch (error) {
      await _store.recordHealth(
        normalized,
        JmHostKind.api,
        ok: false,
        latencyMs: sw.elapsedMilliseconds,
        status: _statusOf(error),
      );
      Log.w('分流切换 $normalized 失败：$error');
      return false;
    }
  }

  Future<void> ensurePrepared() async {
    if (_prepared) return;
    await prepare();
  }

  // ---------------------------------------------------------------- 首页端点
  @override
  Future<List<JmPromoteModule>> fetchPromote() async {
    final decoded = await _requestApi('/promote');
    return JmResponseParser.promote(decoded);
  }

  @override
  Future<List<JmAlbumSummary>> fetchLatest({int page = 1}) async {
    final decoded = await _requestApi(
      '/latest',
      query: <String, String>{'page': '$page'},
    );
    return JmResponseParser.albumList(decoded);
  }

  @override
  Future<List<JmCategory>> fetchCategories() async {
    final decoded = await _requestApi(
      '/categories',
      query: <String, String>{'page': '1'},
    );
    return JmResponseParser.categories(decoded);
  }

  @override
  Future<JmSearchPage> fetchFilter({
    int page = 1,
    String category = '0',
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    final decoded = await _requestApi(
      '/categories/filter',
      query: <String, String>{
        'page': '$page',
        'order': '',
        'c': category,
        'o': order.code,
      },
    );
    return JmResponseParser.searchPage(decoded, page: page);
  }

  @override
  Future<JmSearchPage> search({
    required String query,
    int page = 1,
    AlbumOrder order = AlbumOrder.latestUpdate,
  }) async {
    final decoded = await _requestApi(
      '/search',
      query: <String, String>{
        'main_tag': '0',
        'search_query': query,
        'page': '$page',
        'o': order.code,
        't': 'a',
      },
    );
    return JmResponseParser.searchPage(decoded, page: page, query: query);
  }

  // ---------------------------------------------------------------- 详情 / 章节
  @override
  Future<JmAlbumDetail> getAlbum(String albumId) async {
    final root = await _requestApi(
      '/album',
      query: <String, String>{'id': albumId},
    );
    final map = asMap(root);
    if (map == null) {
      throw const JmApiException('专辑响应结构异常', network: true);
    }
    final album = JmResponseParser.album(map, albumId);
    final seriesId = album.seriesId.trim();
    if (seriesId.isNotEmpty && seriesId != '0' && seriesId != album.id) {
      // 传进来的可能是章节号：按 series_id 再取一次详情。
      final redirectRoot = await _requestApi(
        '/album',
        query: <String, String>{'id': seriesId},
      );
      final redirectMap = asMap(redirectRoot);
      if (redirectMap != null) {
        return JmResponseParser.album(redirectMap, seriesId);
      }
    }
    return album;
  }

  @override
  Future<JmChapter> getChapter(JmChapterRef reference) async {
    final root = await _requestApi(
      '/chapter',
      query: <String, String>{'id': reference.id},
    );
    final map = asMap(root);
    if (map == null) {
      throw const JmApiException('章节响应结构异常', network: true);
    }
    return JmResponseParser.chapter(map, reference);
  }

  @override
  Future<int> getScrambleId(String photoId) async {
    final ts = _timestamp();
    final query = <String, String>{
      'id': photoId,
      'mode': 'vertical',
      'page': '0',
      'app_img_shunt': '1',
      'express': 'off',
      'v': ts,
    };
    final hosts = _preferActive(
      _orderedHosts(_store.apiHosts, JmHostKind.api),
      _activeHost,
      JmHostKind.api,
    );
    Object? lastError;
    final deadline = DateTime.now().add(JmConstants.requestTotalBudget);
    for (final host in hosts) {
      if (lastError != null && DateTime.now().isAfter(deadline)) break;
      final sw = Stopwatch()..start();
      try {
        final response = await _dio.get<String>(
          'https://$host/chapter_view_template',
          queryParameters: query,
          options: Options(
            responseType: ResponseType.plain,
            receiveTimeout: JmConstants.requestAttemptTimeout,
            sendTimeout: JmConstants.requestAttemptTimeout,
            headers: <String, dynamic>{
              'User-Agent': JmConstants.userAgent,
              'token': JmCrypto.buildToken(
                ts,
                secret: JmConstants.scrambleTokenSecret,
              ),
              'tokenparam': '$ts,${_store.appVersion}',
            },
          ),
        );
        final html = response.data ?? '';
        final match = RegExp(JmConstants.scrambleIdPattern).firstMatch(html);
        await _store.recordHealth(
          host,
          JmHostKind.api,
          ok: true,
          latencyMs: sw.elapsedMilliseconds,
          status: 'ok',
        );
        if (match == null) {
          Log.w(
            '章节线路 $host 未匹配到 scramble_id，回落 ${JmConstants.defaultScrambleId}',
          );
          return JmConstants.defaultScrambleId;
        }
        return int.tryParse(match.group(1) ?? '') ??
            JmConstants.defaultScrambleId;
      } catch (error) {
        lastError = error;
        await _store.recordHealth(
          host,
          JmHostKind.api,
          ok: false,
          latencyMs: sw.elapsedMilliseconds,
          status: 'error',
        );
        Log.w('scramble 线路 $host 失败：$error');
      }
    }
    throw JmApiException(
      '获取章节阈值失败：${lastError ?? "所有 API 线路均不可用"}',
      network: true,
    );
  }

  // ---------------------------------------------------------------- 图片
  @override
  String coverUrl(String albumId) {
    final host = imageHost.replaceFirst(RegExp(r'^https?://'), '');
    return 'https://$host/media/albums/${albumId}_3x4.jpg';
  }

  @override
  String photoUrl(String photoId, String filename) {
    final host = imageHost.replaceFirst(RegExp(r'^https?://'), '');
    return 'https://$host/media/photos/$photoId/$filename';
  }

  // ---------------------------------------------------------------- 账号 / 收藏
  @override
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final decoded = await _requestApi(
      '/login',
      method: 'POST',
      form: <String, String>{'username': username, 'password': password},
    );
    final map = asMap(decoded);
    if (map == null) {
      throw const JmContentException('登录响应结构异常');
    }
    final avs = asString(map['s']);
    if (avs != null && avs.isNotEmpty) {
      await setCookie('AVS', avs);
    }
    return map;
  }

  @override
  Future<JmFavoriteList> fetchFavorites({
    int page = 1,
    String order = 'mr',
    int folderId = 0,
  }) async {
    final decoded = await _requestApi(
      '/favorite',
      query: <String, String>{
        'page': '$page',
        'o': order,
        'folder_id': '$folderId',
      },
    );
    final map = asMap(decoded);
    if (map == null) {
      throw const JmContentException('收藏列表结构异常');
    }
    return JmFavoriteList.fromJson(map, page: page);
  }

  @override
  Future<String> toggleFavorite(String albumId) async {
    final decoded = await _requestApi(
      '/favorite',
      method: 'POST',
      form: <String, String>{'aid': albumId},
    );
    final map = asMap(decoded);
    final type = asString(map?['type']) ?? '';
    if (type != 'add' && type != 'remove') {
      throw JmContentException('收藏接口返回无法识别：$type');
    }
    return type;
  }

  @override
  Future<bool> pingFavorite() async {
    try {
      await fetchFavorites(page: 1);
      return true;
    } on JmApiException {
      rethrow;
    } catch (_) {
      // code!=200 / 结构异常：视为未登录或会话失效。
      return false;
    }
  }

  @override
  Future<void> setCookie(String name, String value) async => _jar.setCookie(name, value);

  @override
  Map<String, String> get cookieSnapshot => _jar.snapshot();

  @override
  void restoreCookies(Map<String, String> cookies) => _jar.restore(cookies);
  @override
  Future<Uint8List> downloadImage(String photoId, String filename) async {
    final hosts = _preferActive(
      _orderedHosts(_store.imageHosts, JmHostKind.image),
      _activeImageHost,
      JmHostKind.image,
    );
    if (hosts.isEmpty) {
      throw const JmApiException('图床线路为空', network: true);
    }
    Object? lastError;
    final deadline = DateTime.now().add(JmConstants.imageTotalBudget);
    for (final host in hosts) {
      if (lastError != null && DateTime.now().isAfter(deadline)) break;
      final sw = Stopwatch()..start();
      try {
        final response = await _dio.get<List<int>>(
          'https://$host/media/photos/$photoId/$filename',
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 25),
            sendTimeout: const Duration(seconds: 25),
            headers: <String, dynamic>{
              'User-Agent': JmConstants.userAgent,
              'Accept': JmConstants.imageAccept,
              'X-Requested-With': JmConstants.requestedWith,
              'Referer': 'https://$apiHost/',
            },
          ),
        );
        final contentType =
            (response.headers.value('content-type') ?? '').toLowerCase();
        if (contentType.contains('text/html')) {
          throw JmApiException('图床 $host 返回了网页而不是图片');
        }
        final bytes = response.data;
        if (bytes == null || bytes.isEmpty) {
          throw JmApiException('图床 $host 返回了空图片');
        }
        await _store.markImageHostWorking(host);
        await _store.recordHealth(
          host,
          JmHostKind.image,
          ok: true,
          latencyMs: sw.elapsedMilliseconds,
          status: 'ok',
        );
        _activeImageHost = host;
        return Uint8List.fromList(bytes);
      } catch (error) {
        lastError = error;
        await _store.recordHealth(
          host,
          JmHostKind.image,
          ok: false,
          latencyMs: sw.elapsedMilliseconds,
          status: 'error',
        );
        Log.w('图床 $host 失败：$error');
      }
    }
    throw JmApiException(
      '图片 $filename 下载失败：${lastError ?? "所有图床线路均不可用"}',
      network: true,
    );
  }

  // ---------------------------------------------------------------- 底层
  Future<dynamic> _requestApi(
    String path, {
    Map<String, String>? query,
    String tokenSecret = JmConstants.tokenSecret,
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    final hosts = _preferActive(
      _orderedHosts(_store.apiHosts, JmHostKind.api),
      _activeHost,
      JmHostKind.api,
    );
    if (hosts.isEmpty) {
      throw const JmApiException('没有可用 API 线路，请到「我的 - 网络」手动填写域名');
    }
    final failures = <String>[];
    final deadline = DateTime.now().add(JmConstants.requestTotalBudget);
    Object? lastError;
    for (final host in hosts) {
      // 总预算到点就停：宁可报「部分线路超时」，也不让首屏等满 7 台。
      if (failures.isNotEmpty && DateTime.now().isAfter(deadline)) {
        failures.add('剩余 ${hosts.length - failures.length} 台因总预算用尽未尝试');
        break;
      }
      final sw = Stopwatch()..start();
      try {
        final decoded = await _requestApiOnHost(
          host,
          path,
          query: query,
          tokenSecret: tokenSecret,
          method: method,
          form: form,
        );
        await _store.markApiHostWorking(host);
        await _store.recordHealth(
          host,
          JmHostKind.api,
          ok: true,
          latencyMs: sw.elapsedMilliseconds,
          status: 'ok',
        );
        _activeHost = host;
        return decoded;
      } on JmContentException {
        // 接口语义错误（code != 200）：线路本身是通的，不换线、也不记失败。
        await _store.recordHealth(
          host,
          JmHostKind.api,
          ok: true,
          latencyMs: sw.elapsedMilliseconds,
          status: 'content_error',
        );
        rethrow;
      } catch (error) {
        lastError = error;
        await _store.recordHealth(
          host,
          JmHostKind.api,
          ok: false,
          latencyMs: sw.elapsedMilliseconds,
          status: _statusOf(error),
        );
        failures.add('$host（${_describe(error)}）');
        Log.w('API 线路 $host$path 失败：$error');
      }
    }
    throw JmApiException(
      '所有 API 线路均连接失败：${failures.isEmpty ? _describe(lastError) : failures.join('；')}',
      network: true,
      cause: lastError,
    );
  }

  /// 健康度排序后的尝试顺序：冷却中的失败线路排到最后；
  /// 手填线路不参与冷却（用户的显式选择）；若全部都在冷却，则强试前两条。
  List<String> _orderedHosts(List<String> hosts, JmHostKind kind) {
    if (hosts.isEmpty) return const <String>[];
    if (!_autoSwitchHost()) return <String>[hosts.first];
    final manual = JmEndpointResolver.normalizeHost(_store.manualHost);
    final usable = hosts
        .where((host) => host == manual || !_store.isCoolingDown(host, kind))
        .toList(growable: false);
    if (usable.isNotEmpty) return usable;
    return hosts.take(2).toList(growable: false);
  }

  /// 会话粘性：上次成功的线路排到最前（手填线路除外，它已经是用户显式选择）。
  ///
  /// 图床同理：`/setting.img_host` 当天会轮换，粘住它能少一次 302/403 探测。
  List<String> _preferActive(
    List<String> hosts,
    String active,
    JmHostKind kind,
  ) {
    if (active.isEmpty || hosts.length < 2) return hosts;
    if (_store.isCoolingDown(active, kind)) return hosts;
    final manual = JmEndpointResolver.normalizeHost(_store.manualHost);
    if (manual != null && manual.isNotEmpty && manual != active) return hosts;
    final index = hosts.indexOf(active);
    if (index <= 0) return hosts;
    final ordered = List<String>.of(hosts, growable: true);
    ordered.removeAt(index);
    ordered.insert(0, active);
    return ordered;
  }

  static String _statusOf(Object error) {
    if (error is DioException) {
      return switch (error.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          'timeout',
        DioExceptionType.badCertificate => 'tls_error',
        DioExceptionType.badResponse =>
          'http_${error.response?.statusCode ?? 0}',
        DioExceptionType.connectionError => 'connection_error',
        _ => 'error',
      };
    }
    if (error is JmApiException) {
      // 把「通了但用不了」的原因带到健康表，设置页能直接看出是协议问题还是网络问题。
      final message = error.message;
      if (message.contains('非 JSON')) return 'not_json';
      if (message.contains('解密')) return 'decrypt_failed';
      if (message.contains('解析')) return 'not_json';
      if (message.contains('结构异常')) return 'payload_unexpected';
      return 'bad_response';
    }
    return 'error';
  }

  Future<dynamic> _requestApiOnHost(
    String host,
    String path, {
    Map<String, String>? query,
    required String tokenSecret,
    String method = 'GET',
    Map<String, String>? form,
  }) async {
    final ts = _timestamp();
    final Response<String> response;
    try {
      response = await _dio.request<String>(
        'https://$host$path',
        data: form == null ? null : FormData.fromMap(form),
        queryParameters: query,
        options: Options(
          method: method,
          responseType: ResponseType.plain,
          receiveTimeout: JmConstants.requestAttemptTimeout,
          sendTimeout: JmConstants.requestAttemptTimeout,
          headers: <String, dynamic>{
            'User-Agent': JmConstants.userAgent,
            // 不手动设 Accept-Encoding：交给 HttpClient 自动 gzip。
            'token': JmCrypto.buildToken(ts, secret: tokenSecret),
            'tokenparam': '$ts,${_store.appVersion}',
          },
        ),
      );
    } on DioException catch (error) {
      throw JmApiException(
        'API 线路 $host 返回异常：${_describe(error)}',
        cause: error,
      );
    }

    final text = response.data ?? '';
    final jsonText = extractJsonObject(text);
    if (jsonText == null) {
      throw JmApiException('API 线路 $host 返回了非 JSON 响应（可能被重定向到引导页）');
    }

    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(jsonText);
      final map = asMap(decoded);
      if (map == null) {
        throw const FormatException('响应根节点不是对象');
      }
      envelope = map;
    } catch (error) {
      throw JmApiException('API 线路 $host 的响应解析失败', cause: error);
    }

    final code = asInt(envelope['code'], 200);
    if (code != 200) {
      final message = asString(envelope['errorMsg']) ??
          asString(envelope['msg']) ??
          'HTTP 200，接口 code=$code';
      throw JmContentException('JM 接口错误：$message');
    }

    final data = asString(envelope['data']);
    if (data == null || data.isEmpty) {
      throw const JmContentException('JM 接口没有返回数据');
    }

    try {
      return jsonDecode(JmCrypto.decryptPayload(data, ts));
    } catch (error) {
      throw JmApiException('API 线路 $host 的响应解密失败', cause: error);
    }
  }

  /// 从可能被 HTML 包裹的响应里截出第一个 `{...}`（对齐 Kotlin `extractJsonObject`）。
  static String? extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end < start) return null;
    return text.substring(start, end + 1);
  }

  String _timestamp() =>
      timestampProvider?.call() ??
      (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
  static String _describe(Object? error) {
    if (error == null) return '未知网络错误';
    if (error is DioException) {
      final type = error.type.name;
      final message = error.message ?? error.error?.toString() ?? '';
      return message.isEmpty ? type : '$type: $message';
    }
    return error.toString();
  }
}
