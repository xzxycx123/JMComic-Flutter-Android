import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../core/utils/host_normalizer.dart';
import '../models/jm_host_entry.dart';
import '../models/json_field.dart';

/// 线路清单解析器：把「四个来源」的原始文本统一成 [JmHostEntry]。
///
/// 四个来源（按可靠性排序）：
/// 1. 官方域名服务：AES 解密后的 `{"Setting":[],"Server":[],"jm3_Server":[[host,label],…]}`；
/// 2. 发布页 HTML：`div.international / .southeast_asia / .china / .first_line / .second_line`；
/// 3. 开源项目配置（GitHub raw）：`DOMAIN_API_LIST` / `DOMAIN_IMAGE_LIST` 两个三引号块；
/// 4. 打包进 APK 的种子 `assets/data/jm_hosts.json`。
abstract final class JmHostCatalog {
  // ---------------------------------------------------------------- 1. 种子文件
  /// 解析 `assets/data/jm_hosts.json`（schema 2：`{api:[],image:[],web:[]}`）。
  static List<JmHostEntry> parseSeed(String jsonText) {
    if (jsonText.trim().isEmpty) return const <JmHostEntry>[];
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return const <JmHostEntry>[];
    }
    final root = asMap(decoded);
    if (root == null) return const <JmHostEntry>[];
    final entries = <JmHostEntry>[];
    for (final kind in JmHostKind.values) {
      for (final item in asList(root[kind.code])) {
        final map = asMap(item);
        if (map == null) continue;
        final entry = JmHostEntry.fromJson(map, kind: kind);
        if (entry.host.isNotEmpty) entries.add(entry);
      }
    }
    return entries;
  }

  // ---------------------------------------------------------------- 2. 域名服务
  /// 解析域名服务明文。
  ///
  /// `Setting` 与 `Server` 只有主机名；`jm3_Server` 是 `[host, 線路N]` 二元组，
  /// 旧实现只读 `Server`，把最有用的标签和 `www.cdnutc.me` 全丢了。
  static List<JmHostEntry> parseDomainServer(dynamic payload) {
    final dynamic decoded;
    if (payload is String) {
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        return const <JmHostEntry>[];
      }
    } else {
      decoded = payload;
    }
    final root = asMap(decoded);
    if (root == null) return const <JmHostEntry>[];

    final entries = <JmHostEntry>[];

    for (final key in <String>['Setting', 'Server']) {
      for (final raw in asStringList(root[key])) {
        final host = normalizeHost(raw);
        if (host == null) continue;
        entries.add(JmHostEntry(
            host: host, kind: JmHostKind.api, sources: <String>['tos:$key'],),);
      }
    }

    for (final item in asList(root['jm3_Server'])) {
      final pair = asList(item);
      if (pair.isEmpty) continue;
      final host = normalizeHost(asString(pair.first) ?? '');
      if (host == null) continue;
      final label = pair.length > 1 ? (asString(pair[1]) ?? '').trim() : '';
      entries.add(
        JmHostEntry(
          host: host,
          kind: JmHostKind.api,
          label: label,
          sources: const <String>['tos:jm3_Server'],
        ),
      );
    }

    return merge(entries);
  }

  // ---------------------------------------------------------------- 3. 发布页
  /// 发布页分区 -> (展示名, 是否国内)。
  static const Map<String, ({String label, bool domestic})>
      publicationSections = <String, ({String label, bool domestic})>{
    'international': (label: '國際通用', domestic: false),
    'southeast_asia': (label: '東南亞', domestic: false),
    'china': (label: '內地', domestic: true),
    'first_line': (label: '分流1', domestic: true),
    'second_line': (label: '分流2', domestic: true),
  };

  /// 解析发布页（jmcomictt.site / jmcomicgo.org）的域名列表。
  static List<JmHostEntry> parsePublication(String htmlText) {
    if (htmlText.trim().isEmpty) return const <JmHostEntry>[];
    final dom.Document document;
    try {
      document = html_parser.parse(htmlText);
    } catch (_) {
      return const <JmHostEntry>[];
    }

    final entries = <JmHostEntry>[];
    for (final section in publicationSections.entries) {
      final meta = section.value;
      for (final span in document.querySelectorAll('div.${section.key} span')) {
        final host = normalizeHost(span.text);
        if (host == null) continue;
        entries.add(
          JmHostEntry(
            host: host,
            kind: JmHostKind.web,
            label: meta.label,
            domestic: meta.domestic || isDomesticHost(host),
            sources: const <String>['pub'],
          ),
        );
      }
    }
    return merge(entries);
  }

  // ---------------------------------------------------------------- 4. 开源镜像
  static final RegExp _apiListPattern = RegExp(
    "DOMAIN_API_LIST\\s*=\\s*shuffled\\(\\s*'''(.+?)'''\\s*\\)",
    dotAll: true,
  );
  static final RegExp _imageListPattern = RegExp(
    "DOMAIN_IMAGE_LIST\\s*=\\s*shuffled\\(\\s*'''(.+?)'''\\s*\\)",
    dotAll: true,
  );

  /// 解析 JMComic-Crawler-Python 的 `jm_config.py`。
  static List<JmHostEntry> parseMirrorConfig(String text) {
    if (text.trim().isEmpty) return const <JmHostEntry>[];
    final entries = <JmHostEntry>[];
    void collect(RegExp pattern, JmHostKind kind, String source) {
      final match = pattern.firstMatch(text);
      if (match == null) return;
      for (final line in (match.group(1) ?? '').split('\n')) {
        final host = normalizeHost(line.trim());
        if (host == null) continue;
        entries.add(
            JmHostEntry(host: host, kind: kind, sources: <String>[source]),);
      }
    }

    collect(_apiListPattern, JmHostKind.api, 'github:apiList');
    collect(_imageListPattern, JmHostKind.image, 'github:imageList');
    return merge(entries);
  }

  // ---------------------------------------------------------------- 合并
  /// 按 `kind|host` 去重：保留首条的标签/国内标记，sources 取并集。
  static List<JmHostEntry> merge(Iterable<JmHostEntry> entries) {
    final result = <String, JmHostEntry>{};
    for (final entry in entries) {
      if (entry.host.isEmpty) continue;
      final key = '${entry.kind.code}|${entry.host}';
      final existing = result[key];
      if (existing == null) {
        result[key] = entry;
        continue;
      }
      final sources = <String>{...existing.sources, ...entry.sources}
          .toList(growable: false);
      // 状态合并：ok 优先（任一源实测可用就算可用），否则保留已知结论。
      final status = existing.status == 'unknown'
          ? entry.status
          : (entry.status == 'ok' ? 'ok' : existing.status);
      final bestLatency = <int>[
        if (existing.status == 'ok' && existing.latencyMs > 0)
          existing.latencyMs,
        if (entry.status == 'ok' && entry.latencyMs > 0) entry.latencyMs,
      ].fold<int>(0, (best, value) => best == 0 || value < best ? value : best);
      result[key] = existing.copyWith(
        label: existing.label.isEmpty ? entry.label : existing.label,
        domestic: existing.domestic || entry.domestic,
        sources: sources,
        status: status,
        latencyMs: bestLatency == 0 ? existing.latencyMs : bestLatency,
        settingImgHost: existing.settingImgHost.isEmpty
            ? entry.settingImgHost
            : existing.settingImgHost,
        appVersion: existing.appVersion.isEmpty
            ? entry.appVersion
            : existing.appVersion,
        checkedAt:
            existing.checkedAt.isEmpty ? entry.checkedAt : existing.checkedAt,
      );
    }
    return result.values.toList(growable: false);
  }

  /// 按用途取主机名（去重、保序）。
  static List<String> hostsOf(Iterable<JmHostEntry> entries, JmHostKind kind) {
    final seen = <String>{};
    final hosts = <String>[];
    for (final entry in entries) {
      if (entry.kind != kind) continue;
      if (entry.host.isEmpty) continue;
      if (seen.add(entry.host)) hosts.add(entry.host);
    }
    return hosts;
  }
}
