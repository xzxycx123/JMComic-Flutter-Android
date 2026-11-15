import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/host_normalizer.dart';
import '../../core/utils/logger.dart';
import '../local/endpoint_store.dart';
import '../models/jm_host_entry.dart';
import 'jm_crypto.dart';
import 'jm_host_catalog.dart';
import 'jm_host_probe.dart';

/// 一次「发现 + 实测」的结果快照（设置页 / 日志 / 排障都用它）。
class JmDiscoveryReport {
  const JmDiscoveryReport({
    required this.at,
    required this.sources,
    required this.candidates,
    required this.probes,
    required this.apiHosts,
    required this.imageHosts,
    this.message = '',
  });

  final DateTime at;

  /// 本次真正跑通的发现源：`seed` / `tos` / `pub` / `mirror` / `builtin`。
  final List<String> sources;

  /// 去重后的候选线路数。
  final int candidates;
  final List<JmHostProbeResult> probes;
  final List<String> apiHosts;
  final List<String> imageHosts;
  final String message;

  int get okCount => probes.where((probe) => probe.ok).length;

  List<JmHostProbeResult> get failedProbes =>
      probes.where((probe) => !probe.ok).toList(growable: false);

  String get summary {
    final sourceText = sources.isEmpty ? '无源' : sources.join('+');
    return '$sourceText · 候选 $candidates · 实测 ${probes.length} 台 · 可用 $okCount 台';
  }
}

/// 域名发现 + 线路挑选（PLAN §5.2 的加强版）。
///
/// 旧实现的问题（本次修的就是这些）：
/// 1. 只认 3 个 TOS 源，全部失败就只剩过期硬编码；
/// 2. 只读 `Server`，把 `jm3_Server` 的线路标签和第 5 条线路丢掉；
/// 3. 只要 HTTP 200 就算「发现成功」，不验证接口是否真能用；
/// 4. 没有任何国内地址兜底，图床也只认海外 CDN；
/// 5. 探测结果不落盘，每次冷启动都重新撞一遍死线路。
///
/// 现在的顺序：
/// `内置种子 -> TOS 域名服务 -> 发布页（国内域名）-> GitHub 镜像配置 -> 内置兜底`，
/// 合并去重后按「首批 4 台并发实测、有 ok 即停」做连通性验证，结果写进 [EndpointStore] 健康表。
class JmEndpointResolver {
  JmEndpointResolver({
    required Dio dio,
    required EndpointStore store,
    required JmHostProbe probe,
    Future<String?> Function(String assetPath)? seedLoader,
    Future<String?> Function(String url)? textLoader,
    this.sourceTimeout = const Duration(seconds: 6),
    this.probeTimeout = JmConstants.probeTimeout,
    this.maxProbes = 8,
    this.probeConcurrency = 4,
    this.probeBatch = 4,
  })  : _store = store,
        _probe = probe,
        _seedLoader = seedLoader ?? _loadAsset,
        _textLoader = textLoader ?? dioTextLoader(dio, timeout: sourceTimeout);

  final EndpointStore _store;
  final JmHostProbe _probe;
  final Future<String?> Function(String assetPath) _seedLoader;
  final Future<String?> Function(String url) _textLoader;

  final Duration sourceTimeout;
  final Duration probeTimeout;
  final int maxProbes;
  final int probeConcurrency;
  final int probeBatch;

  JmDiscoveryReport? _lastReport;
  Future<JmDiscoveryReport>? _inflight;

  /// 最近一次报告（没跑过就是 null）。
  JmDiscoveryReport? get lastReport => _lastReport;

  // ---------------------------------------------------------------- 对外入口
  /// 冷启动用：3 分钟内复用上次结果，避免每次进首页都重新发现 + 实测。
  Future<JmDiscoveryReport> refresh({bool force = false}) {
    final cached = _lastReport;
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 3)) {
      return Future<JmDiscoveryReport>.value(cached);
    }
    final inflight = _inflight;
    if (inflight != null) return inflight;
    final future = _run(force: force);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  /// 设置页「全部测速」：不看缓存、不设上限，把所有已知线路都跑一遍。
  Future<JmDiscoveryReport> probeAll({bool refreshSources = true}) async {
    final collected = refreshSources
        ? await _collect()
        : _lastCollected ?? const _Collected.empty();
    final apiHosts = _mergeHosts(<String>[
      ...JmHostCatalog.hostsOf(collected.entries, JmHostKind.api),
      ..._store.apiHosts,
    ]);
    final results = <JmHostProbeResult>[
      ...await _probe.probeApis(
        apiHosts,
        concurrency: 6,
        timeout: probeTimeout,
      ),
    ];
    for (final result in results) {
      await _store.recordHealth(
        result.host,
        JmHostKind.api,
        ok: result.ok,
        latencyMs: result.latencyMs,
        status: result.status,
      );
    }

    final okHosts = results.where((result) => result.ok).toList(growable: false)
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    if (okHosts.isNotEmpty) {
      await _store.applyDiscoveredHosts(
        okHosts.map((result) => result.host).toList(growable: false),
      );
    }

    final images = <String>{
      for (final result in okHosts)
        if (result.imgHost.isNotEmpty) result.imgHost,
      ...JmHostCatalog.hostsOf(collected.entries, JmHostKind.image),
      ...JmConstants.domesticHosts,
      ..._store.imageHosts,
    };
    final imageResults = await _probe.probeImages(images, concurrency: 6);
    final okImages = <String>[];
    for (final result in imageResults) {
      await _store.recordHealth(
        result.host,
        JmHostKind.image,
        ok: result.ok,
        latencyMs: result.latencyMs,
        status: result.status,
      );
      if (result.ok) okImages.add(result.host);
    }
    if (okImages.isNotEmpty) {
      await _store.setImageHosts(okImages);
      await _store.markImageHostWorking(okImages.first);
    }

    final report = JmDiscoveryReport(
      at: DateTime.now(),
      sources: collected.sources,
      candidates: apiHosts.length,
      probes: <JmHostProbeResult>[...results, ...imageResults],
      apiHosts: _store.apiHosts,
      imageHosts: _store.imageHosts,
      message: '全量测速完成',
    );
    _lastReport = report;
    _lastCollected = collected;
    return report;
  }

  /// 兼容旧调用：只要线路列表。
  Future<List<String>> discover() async => (await refresh()).apiHosts;  Future<List<String>> applyAndRank() async => _store.apiHosts;

  // ---------------------------------------------------------------- 主流程
  /// 冷启动快路径：上次成功且仍在健康 TTL 内的线路直接复用，零网络请求。
  JmDiscoveryReport? _fastPath() {
    final last = normalizeHost(_store.lastApiHost);
    if (last == null) return null;
    final health = _store.healthOf(last, JmHostKind.api);
    if (health == null || !health.ok || !health.isFresh(JmConstants.healthTtl)) {
      return null;
    }
    final report = JmDiscoveryReport(
      at: DateTime.now(),
      sources: const <String>['cache'],
      candidates: _store.apiHosts.length,
      probes: const <JmHostProbeResult>[],
      apiHosts: _store.apiHosts,
      imageHosts: _store.imageHosts,
      message: '复用上次成功线路 $last',
    );
    _lastReport = report;
    Log.i('线路快路径：复用上次成功线路 $last');
    return report;
  }

  Future<JmDiscoveryReport> _run({required bool force}) async {
    // 冷启动快路径：上次成功且 30 分钟内仍健康的线路，直接用，不再跑任何发现/探测。
    if (!force) {
      final fast = _fastPath();
      if (fast != null) return fast;
    }

    final collected = await _collect();
    _lastCollected = collected;

    final manual = normalizeHost(_store.manualHost);
    final candidates = _mergeHosts(<String>[
      if (manual != null) manual,
      ...JmHostCatalog.hostsOf(collected.entries, JmHostKind.api),
      ..._store.apiHosts,
    ]);

    // 先把打包种子里的实测结论回填成健康记录：命中 TTL 内就直接用，冷启动不必先等一轮探测。
    final ingested = await _ingestSeedHealth(collected.entries);

    // 只要已经有一条「新鲜且可用」的线路，就不在冷启动路径上再跑探测：
    // 真正的失败由业务请求自己触发（失败会写健康表 + 冷却），把首屏时间留给首页。
    final hasFreshOk = candidates.any((host) {
      final health = _store.healthOf(host, JmHostKind.api);
      return health != null &&
          health.ok &&
          health.isFresh(JmConstants.healthTtl);
    });

    // 只测「没有新鲜健康记录」的线路：首批 maxProbes 台，4 台一批，有 ok 就停。
    final pending = hasFreshOk
        ? const <String>[]
        : candidates
            .where((host) => !_store.hasFreshHealth(host, JmHostKind.api))
            .take(maxProbes)
            .toList(growable: false);

    final probes = <JmHostProbeResult>[];
    final batchSize = probeBatch <= 0 ? 4 : probeBatch;
    for (var start = 0; start < pending.length; start += batchSize) {
      final batch =
          pending.sublist(start, math.min(start + batchSize, pending.length));
      final results = await _probe.probeApis(
        batch,
        concurrency: probeConcurrency,
        timeout: probeTimeout,
      );
      probes.addAll(results);
      for (final result in results) {
        await _store.recordHealth(
          result.host,
          JmHostKind.api,
          ok: result.ok,
          latencyMs: result.latencyMs,
          status: result.status,
        );
      }
      if (results.any((result) => result.ok)) break;
    }

    final okProbes = probes.where((result) => result.ok).toList(growable: false)
      ..sort((a, b) => a.latencyMs.compareTo(b.latencyMs));
    // 发现的候选全部纳入持久化线路表（排序交给健康度）：这样种子/发布页新域名下次直接可用，
    // 不再要求「本次必须探测成功」才落盘。
    await _store.applyDiscoveredHosts(<String>[
      ...okProbes.map((result) => result.host),
      ...candidates,
    ]);

    // 图床：/setting.img_host 优先，其次是种子/默认里实测 ok 的，最后是国内地址兜底。
    final images = <String>{
      for (final result in okProbes)
        if (result.imgHost.isNotEmpty) result.imgHost,
      for (final entry in collected.entries)
        if (entry.kind == JmHostKind.image && entry.isOk) entry.host,
      ...JmConstants.domesticHosts,
    };
    if (images.isNotEmpty) {
      await _store.setImageHosts(images.toList(growable: false));
    }

    final apiHosts = _store.apiHosts;
    final topHealth = apiHosts.isEmpty
        ? null
        : _store.healthOf(apiHosts.first, JmHostKind.api);
    final message = probes.isEmpty
        ? (topHealth != null && topHealth.ok
            ? '沿用${ingested ? '内置种子' : '缓存'}结论：首选 ${apiHosts.first}（${topHealth.latencyMs}ms）'
            : '尚未实测，等首次请求验证线路')
        : (okProbes.isEmpty
            ? '本次没有探测到可用 API 线路：请检查网络，或在「网络」里手填域名'
            : '首选 ${okProbes.first.host}（${okProbes.first.latencyMs}ms）');

    final report = JmDiscoveryReport(
      at: DateTime.now(),
      sources: collected.sources,
      candidates: candidates.length,
      probes: probes,
      apiHosts: apiHosts,
      imageHosts: _store.imageHosts,
      message: message,
    );
    _lastReport = report;
    Log.i('线路发现完成：${report.summary}；$message');
    return report;
  }

  // ---------------------------------------------------------------- 发现源
  _Collected? _lastCollected;

  /// 把种子文件里的实测结论回填成健康记录（只补「还没有记录」的 host）。
  ///
  /// 时间戳用种子里的 `checkedAt`：种子里写的是构建时的实测时间，
  /// 只要还在 [JmConstants.healthTtl] 内就直接参与排序，过期会自动重测。
  Future<bool> _ingestSeedHealth(List<JmHostEntry> entries) async {
    var ingested = false;
    for (final entry in entries) {
      if (entry.kind != JmHostKind.api) continue;
      if (entry.checkedAt.isEmpty) continue;
      if (_store.healthOf(entry.host, JmHostKind.api) != null) continue;
      final checkedAt =
          DateTime.tryParse(entry.checkedAt)?.millisecondsSinceEpoch;
      if (checkedAt == null) continue;
      await _store.recordHealth(
        entry.host,
        JmHostKind.api,
        ok: entry.isOk,
        latencyMs: entry.latencyMs,
        status: entry.status,
        checkedAt: checkedAt,
      );
      ingested = true;
    }
    return ingested;
  }

  Future<_Collected> _collect() async {
    final entries = <JmHostEntry>[];
    final sources = <String>[];

    // 1) 打包进 APK 的种子（唯一不依赖网络的源）
    final seedText = await _seedLoader(JmConstants.hostSeedAsset);
    if (seedText != null && seedText.isNotEmpty) {
      final parsed = JmHostCatalog.parseSeed(seedText);
      if (parsed.isNotEmpty) {
        entries.addAll(parsed);
        sources.add('seed');
      }
    }

    // 2) 三个 TOS 域名服务：解密后是 Setting / Server / jm3_Server 三张表
    final tasks = <Future<void>>[];
    for (final url in JmConstants.domainServerUrls) {
      tasks.add(_collectDomainServer(url, entries, sources));
    }
    // 3) 发布页：国内域名的唯一来源
    for (final url in JmConstants.publicationUrls) {
      tasks.add(_collectPublication(url, entries, sources));
    }
    // 4) 开源项目镜像配置
    for (final url in JmConstants.domainMirrorUrls) {
      tasks.add(_collectMirror(url, entries, sources));
    }
    await Future.wait(tasks);

    // 5) 硬编码兜底：保证任何源都挂掉时也有线路可试
    for (final host in JmConstants.defaultApiHosts) {
      entries.add(JmHostEntry(
          host: host,
          kind: JmHostKind.api,
          sources: const <String>['builtin'],),);
    }
    for (final host in JmConstants.defaultImageHosts) {
      entries.add(JmHostEntry(
          host: host,
          kind: JmHostKind.image,
          sources: const <String>['builtin'],),);
    }
    for (final host in JmConstants.webHosts) {
      entries.add(
        JmHostEntry(
          host: host,
          kind: JmHostKind.web,
          domestic: isDomesticHost(host),
          sources: const <String>['builtin'],
        ),
      );
    }
    if (sources.isNotEmpty) sources.add('builtin');

    final merged = JmHostCatalog.merge(entries);
    return _Collected(
        entries: merged, sources: sources.toSet().toList(growable: false),);
  }

  Future<void> _collectDomainServer(
      String url, List<JmHostEntry> entries, List<String> sources,) async {
    final text = await _safeFetch(url);
    if (text == null || text.trim().isEmpty) return;
    final payload = stripLeadingNonAscii(text);
    if (payload.isEmpty) return;
    try {
      final decrypted = JmCrypto.decryptPayload(
        payload,
        '',
        secret: JmConstants.domainServerSecret,
      );
      final parsed = JmHostCatalog.parseDomainServer(decrypted);
      if (parsed.isEmpty) return;
      entries.addAll(parsed);
      sources.add('tos');
    } catch (error) {
      Log.w('域名服务 $url 解密失败：$error');
    }
  }

  Future<void> _collectPublication(
      String url, List<JmHostEntry> entries, List<String> sources,) async {
    final text = await _safeFetch(url);
    if (text == null || !text.contains('<')) return;
    final parsed = JmHostCatalog.parsePublication(text);
    if (parsed.isEmpty) return;
    entries.addAll(parsed);
    sources.add('pub');
  }

  Future<void> _collectMirror(
      String url, List<JmHostEntry> entries, List<String> sources,) async {
    final text = await _safeFetch(url);
    if (text == null || text.isEmpty) return;
    final parsed = JmHostCatalog.parseMirrorConfig(text);
    if (parsed.isEmpty) return;
    entries.addAll(parsed);
    sources.add('mirror');
  }

  Future<String?> _safeFetch(String url) async {
    try {
      final text = await _textLoader(url);
      return text;
    } catch (error) {
      Log.w('发现源 $url 不可用：$error');
      return null;
    }
  }

  // ---------------------------------------------------------------- 工具
  static List<String> _mergeHosts(List<String> hosts) {
    final seen = <String>{};
    final result = <String>[];
    for (final host in hosts) {
      final normalized = normalizeHost(host);
      if (normalized == null) continue;
      if (seen.add(normalized)) result.add(normalized);
    }
    return result;
  }

  /// 去掉开头的非 ASCII 字符（对齐 Kotlin `dropWhile { it.code > 0x7f }`）。
  static String stripLeadingNonAscii(String input) {
    final runes = input.runes.toList(growable: false);
    var start = 0;
    while (start < runes.length && runes[start] > 0x7f) {
      start++;
    }
    return String.fromCharCodes(runes.skip(start)).trim();
  }

  /// `https://host/path` / `host` -> `host`；非法返回 null。
  static String? normalizeHost(String raw) => hostFromUrl(raw);

  static Future<String?> _loadAsset(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (error) {
      Log.w('内置线路种子读取失败（$path）：$error');
      return null;
    }
  }

  /// 给 provider 用的默认 HTTP 读取器（带 UA 与超时）。
  static Future<String?> Function(String url) dioTextLoader(
    Dio dio, {
    Duration timeout = const Duration(seconds: 6),
  }) {
    return (String url) async {
      final response = await dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: timeout,
          sendTimeout: timeout,
          headers: <String, dynamic>{'User-Agent': JmConstants.userAgent},
        ),
      );
      return response.data;
    };
  }
}

class _Collected {
  const _Collected({required this.entries, required this.sources});

  const _Collected.empty()
      : entries = const <JmHostEntry>[],
        sources = const <String>[];

  final List<JmHostEntry> entries;
  final List<String> sources;
}
