import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/jm_constants.dart';
import '../../core/utils/host_normalizer.dart';
import '../models/jm_host_entry.dart';
import '../models/json_field.dart';
import '../models/user_session.dart';

/// 一条线路的健康记录（持久化在 SharedPreferences 的 JSON 串里）。
class JmHostHealth {
  const JmHostHealth({
    required this.host,
    required this.kind,
    required this.ok,
    required this.latencyMs,
    required this.checkedAt,
    this.status = '',
    this.failCount = 0,
  });

  final String host;
  final JmHostKind kind;
  final bool ok;
  final int latencyMs;

  /// 毫秒时间戳。
  final int checkedAt;
  final String status;
  final int failCount;

  int get ageMs => DateTime.now().millisecondsSinceEpoch - checkedAt;

  bool isFresh(Duration ttl) => ageMs < ttl.inMilliseconds;

  bool isCoolingDown(Duration cooldown) => !ok && isFresh(cooldown);

  factory JmHostHealth.fromJson(Map<String, dynamic> json) => JmHostHealth(
        host: asStringOr(json['host'], ''),
        kind: JmHostKind.fromCode(asString(json['kind'])),
        ok: asBool(json['ok']),
        latencyMs: asInt(json['latencyMs']),
        checkedAt: asInt(json['checkedAt']),
        status: asStringOr(json['status'], ''),
        failCount: asInt(json['failCount']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'kind': kind.code,
        'ok': ok,
        'latencyMs': latencyMs,
        'checkedAt': checkedAt,
        'status': status,
        'failCount': failCount,
      };
}

/// 可用线路、图床、健康度的持久化（对齐 JmScript 的 `jm_endpoints` SharedPreferences）。
///
/// 排序规则（[apiHosts] / [imageHosts] 都遵守）：
/// 1. 手填线路永远第一；
/// 2. 最近一次实测 ok 的按延迟升序；
/// 3. 没有记录的（未知）排中间；
/// 4. 失败且还在冷却窗口内的排最后 —— 避免每次点击都先撞一遍死线路。
class EndpointStore {
  EndpointStore(this._prefs);

  static const String _keyApiHosts = 'jm_api_hosts';
  static const String _keyImageHosts = 'jm_image_hosts';
  static const String _keyAppVersion = 'jm_app_version';
  static const String _keyManualHost = 'jm_manual_host';
  static const String _keyUpdatedAt = 'jm_endpoints_updated_at';
  static const String _keyHealth = 'jm_host_health';

  final SharedPreferences _prefs;

  List<String> get apiHosts {
    final candidates = _merge(<String?>[
      manualHost,
      ..._readHosts(_keyApiHosts),
      ...JmConstants.defaultApiHosts,
    ]);
    return _rank(candidates, JmHostKind.api);
  }

  List<String> get imageHosts {
    final candidates = _merge(<String?>[
      ..._readHosts(_keyImageHosts),
      ...JmConstants.domesticHosts,
      ...JmConstants.defaultImageHosts,
    ]);
    return _rank(candidates, JmHostKind.image);
  }

  /// 网页域名（HTML 兜底）：海外在前、国内在后，健康度同样参与排序。
  List<String> get webHosts {
    final candidates = _merge(<String?>[
      ..._readHosts('jm_web_hosts'),
      ...JmConstants.webHosts,
    ]);
    return _rank(candidates, JmHostKind.web);
  }

  String get appVersion {
    final stored = _prefs.getString(_keyAppVersion);
    return (stored == null || stored.isEmpty)
        ? JmConstants.fallbackAppVersion
        : stored;
  }

  String get manualHost => _prefs.getString(_keyManualHost) ?? '';

  int get updatedAt => _prefs.getInt(_keyUpdatedAt) ?? 0;

  bool get hasManualHost => manualHost.trim().isNotEmpty;

  // ---------------------------------------------------------------- 健康度
  List<JmHostHealth> get healthList {
    final raw = _prefs.getString(_keyHealth);
    if (raw == null || raw.isEmpty) return const <JmHostHealth>[];
    try {
      final decoded = jsonDecode(raw);
      return asList(decoded)
          .map(asMap)
          .whereType<Map<String, dynamic>>()
          .map(JmHostHealth.fromJson)
          .where((item) => item.host.isNotEmpty)
          .toList(growable: false);
    } on FormatException {
      return const <JmHostHealth>[];
    }
  }

  List<JmHostHealth> get apiHealth => healthList
      .where((item) => item.kind == JmHostKind.api)
      .toList(growable: false);

  JmHostHealth? healthOf(String host, [JmHostKind kind = JmHostKind.api]) {
    final normalized = normalizeHost(host);
    if (normalized == null) return null;
    for (final item in healthList) {
      if (item.host == normalized && item.kind == kind) return item;
    }
    return null;
  }

  bool hasFreshHealth(String host, [JmHostKind kind = JmHostKind.api]) {
    final health = healthOf(host, kind);
    return health != null && health.isFresh(JmConstants.healthTtl);
  }

  bool isCoolingDown(String host, [JmHostKind kind = JmHostKind.api]) {
    final health = healthOf(host, kind);
    return health != null && health.isCoolingDown(JmConstants.hostCooldown);
  }

  /// 记录一次探测/请求的结果（同 host+kind 覆盖，失败累加 failCount）。
  ///
  /// [checkedAt] 只在「回填内置种子的历史结论」时传入（毫秒时间戳），
  /// 让种子里的 ok 能立刻参与排序，同时保持「已经是旧数据」这一事实（TTL 到点会重测）。
  Future<void> recordHealth(
    String host,
    JmHostKind kind, {
    required bool ok,
    required int latencyMs,
    String status = '',
    int? checkedAt,
  }) async {
    final normalized = normalizeHost(host);
    if (normalized == null) return;

    final previous = healthOf(normalized, kind);
    final next = JmHostHealth(
      host: normalized,
      kind: kind,
      ok: ok,
      latencyMs: latencyMs <= 0 ? (previous?.latencyMs ?? 0) : latencyMs,
      checkedAt: checkedAt ?? DateTime.now().millisecondsSinceEpoch,
      status: status,
      failCount: ok ? 0 : (previous?.failCount ?? 0) + 1,
    );

    final kept = healthList
        .where((item) => !(item.host == normalized && item.kind == kind))
        .toList(growable: true)
      ..add(next);
    // 只保留最近 80 条，防止 SharedPreferences 无限膨胀。
    if (kept.length > 80) {
      kept.sort((a, b) => b.checkedAt.compareTo(a.checkedAt));
      kept.removeRange(80, kept.length);
    }
    await _prefs.setString(
      _keyHealth,
      jsonEncode(kept.map((item) => item.toJson()).toList(growable: false)),
    );
  }

  Future<void> resetHealth() async {
    await _prefs.remove(_keyHealth);
  }

  // ---------------------------------------------------------------- 线路表
  List<String> _readHosts(String key) {
    final raw = _prefs.getStringList(key) ?? const <String>[];
    return raw.map(normalizeHost).whereType<String>().toList(growable: false);
  }

  /// 手填线路永远排第一；其余保存项在前，内置兜底在后。
  List<String> _merge(List<String?> hosts) {
    final manual = normalizeHost(manualHost);
    final result = <String>[];
    final seen = <String>{};
    for (final host in <String?>[manual, ...hosts]) {
      if (host == null || host.isEmpty) continue;
      if (seen.add(host)) result.add(host);
    }
    return result;
  }

  List<String> _rank(List<String> hosts, JmHostKind kind) {
    final manual = normalizeHost(manualHost);
    final indexed = hosts.asMap().entries.toList(growable: false);
    indexed.sort((a, b) {
      final rankCompare = _rankOf(a.value, kind, manual)
          .compareTo(_rankOf(b.value, kind, manual));
      if (rankCompare != 0) return rankCompare;
      final latencyA = healthOf(a.value, kind)?.latencyMs ?? 0x7fffffff;
      final latencyB = healthOf(b.value, kind)?.latencyMs ?? 0x7fffffff;
      if (latencyA != latencyB) return latencyA.compareTo(latencyB);
      return a.key.compareTo(b.key);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }

  int _rankOf(String host, JmHostKind kind, String? manual) {
    // 手填线路是用户的显式选择：哪怕上次失败也永远排第一（冷却只影响自动线路）。
    if (manual != null && host == manual) return -1;
    final health = healthOf(host, kind);
    if (health == null) return 1;
    if (health.ok) return 0;
    if (health.isCoolingDown(JmConstants.hostCooldown)) return 2;
    return 1;
  }

  Future<void> applyDiscoveredHosts(List<String> hosts) async {
    final normalized =
        hosts.map(normalizeHost).whereType<String>().toList(growable: false);
    if (normalized.isEmpty) return;
    final merged = <String>[...normalized, ..._readHosts(_keyApiHosts)];
    final unique = merged.toSet().toList(growable: false);
    // 上限 30 条：线路会漂移，表不能无限长。
    await _prefs.setStringList(
      _keyApiHosts,
      unique.length > 30 ? unique.sublist(0, 30) : unique,
    );
    await _prefs.setInt(_keyUpdatedAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> markApiHostWorking(String host) async {
    final normalized = normalizeHost(host);
    if (normalized == null) return;
    final saved = _readHosts(_keyApiHosts);
    if (saved.isNotEmpty && saved.first == normalized) return;
    final next = <String>[
      normalized,
      ...saved.where((item) => item != normalized),
    ];
    await _prefs.setStringList(_keyApiHosts, next);
  }

  Future<void> markImageHostWorking(String host) async {
    final normalized = normalizeHost(host);
    if (normalized == null) return;
    final saved = _readHosts(_keyImageHosts);
    if (saved.isNotEmpty && saved.first == normalized) return;
    final next = <String>[
      normalized,
      ...saved.where((item) => item != normalized),
    ];
    await _prefs.setStringList(_keyImageHosts, next);
  }

  Future<void> markWebHostWorking(String host) async {
    final normalized = normalizeHost(host);
    if (normalized == null) return;
    final saved = _readHosts('jm_web_hosts');
    if (saved.isNotEmpty && saved.first == normalized) return;
    final next = <String>[
      normalized,
      ...saved.where((item) => item != normalized),
    ];
    await _prefs.setStringList('jm_web_hosts', next);
  }

  Future<void> setImageHosts(List<String> hosts) async {
    final normalized =
        hosts.map(normalizeHost).whereType<String>().toList(growable: false);
    if (normalized.isEmpty) return;
    final merged = <String>[...normalized, ..._readHosts(_keyImageHosts)];
    await _prefs.setStringList(
        _keyImageHosts, merged.toSet().toList(growable: false),);
  }

  Future<void> setAppVersion(String version) async {
    final value = version.trim();
    if (value.isEmpty) return;
    final current = appVersion;
    if (_compareVersions(value, current) <= 0) return;
    await _prefs.setString(_keyAppVersion, value);
  }

  Future<void> setManualHost(String host) async {
    final value = host.trim();
    if (value.isEmpty) {
      await _prefs.remove(_keyManualHost);
      return;
    }
    final normalized = normalizeHost(value);
    if (normalized == null) return;
    await _prefs.setString(_keyManualHost, normalized);
  }

  Future<void> clearDiscovered() async {
    await _prefs.remove(_keyApiHosts);
    await _prefs.remove(_keyImageHosts);
    await _prefs.remove('jm_web_hosts');
    await _prefs.remove(_keyUpdatedAt);
    await _prefs.remove(_keyHealth);
  }

  UserSession toSession({
    String apiHost = '',
    String imageHost = '',
    int cookieCount = 0,
    bool ready = false,
    String message = '',
  }) {
    return UserSession(
      apiHost: apiHost,
      imageHost: imageHost,
      appVersion: appVersion,
      cookieCount: cookieCount,
      manualHost: manualHost,
      updatedAt: updatedAt,
      ready: ready,
      message: message,
    );
  }

  static int _compareVersions(String left, String right) {
    final a = left.split('.').map((item) => int.tryParse(item) ?? 0).toList();
    final b = right.split('.').map((item) => int.tryParse(item) ?? 0).toList();
    final size = a.length > b.length ? a.length : b.length;
    for (var index = 0; index < size; index++) {
      final av = index < a.length ? a[index] : 0;
      final bv = index < b.length ? b[index] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}
