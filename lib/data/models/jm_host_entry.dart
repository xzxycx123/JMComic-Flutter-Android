import '../../core/utils/host_normalizer.dart';
import 'json_field.dart';

/// 线路用途：APP 接口 / 图床 / 网页。
enum JmHostKind {
  api('api'),
  image('image'),
  web('web');

  const JmHostKind(this.code);

  final String code;

  static JmHostKind fromCode(String? code) {
    for (final kind in JmHostKind.values) {
      if (kind.code == code) return kind;
    }
    return JmHostKind.api;
  }
}

/// 一条线路记录（种子文件、探测结果、健康记录共用同一套字段）。
///
/// `status` 取值：`ok` / `timeout` / `tls_error` / `http_4xx` / `http_5xx` /
/// `not_json` / `payload_unexpected` / `cloudflare_challenge` / `unknown`。
class JmHostEntry {
  const JmHostEntry({
    required this.host,
    required this.kind,
    this.label = '',
    this.status = 'unknown',
    this.latencyMs = 0,
    this.httpStatus = 0,
    this.domestic = false,
    this.sources = const <String>[],
    this.firstSeen = '',
    this.checkedAt = '',
    this.settingImgHost = '',
    this.appVersion = '',
    this.detail = '',
  });

  final String host;
  final JmHostKind kind;

  /// 服务端给的线路标签（`線路1`）或发布页分区（`內地`）。
  final String label;
  final String status;
  final int latencyMs;
  final int httpStatus;
  final bool domestic;

  /// 该线路是被哪个源收录的：`tos:jm3_Server` / `pub:...` / `github:apiList` / `seed` / `builtin`。
  final List<String> sources;
  final String firstSeen;
  final String checkedAt;

  /// `/setting.img_host`：API 线路会顺带下发当前图床。
  final String settingImgHost;
  final String appVersion;
  final String detail;

  bool get isOk => status == 'ok';

  bool get isUsable => isOk && host.isNotEmpty;

  String get displayLabel => label.isEmpty ? host : '$host（$label）';

  JmHostEntry copyWith({
    String? host,
    JmHostKind? kind,
    String? label,
    String? status,
    int? latencyMs,
    int? httpStatus,
    bool? domestic,
    List<String>? sources,
    String? firstSeen,
    String? checkedAt,
    String? settingImgHost,
    String? appVersion,
    String? detail,
  }) {
    return JmHostEntry(
      host: host ?? this.host,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      status: status ?? this.status,
      latencyMs: latencyMs ?? this.latencyMs,
      httpStatus: httpStatus ?? this.httpStatus,
      domestic: domestic ?? this.domestic,
      sources: sources ?? this.sources,
      firstSeen: firstSeen ?? this.firstSeen,
      checkedAt: checkedAt ?? this.checkedAt,
      settingImgHost: settingImgHost ?? this.settingImgHost,
      appVersion: appVersion ?? this.appVersion,
      detail: detail ?? this.detail,
    );
  }

  factory JmHostEntry.fromJson(Map<String, dynamic> json, {JmHostKind? kind}) {
    final host = normalizeHost(asStringOr(json['host'], '')) ?? '';
    final resolvedKind = kind ?? JmHostKind.fromCode(asString(json['kind']));
    return JmHostEntry(
      host: host,
      kind: resolvedKind,
      label: asStringOr(json['label'], ''),
      status: asStringOr(json['status'], 'unknown'),
      latencyMs: asInt(json['latencyMs']),
      httpStatus: asInt(json['httpStatus']),
      domestic: asBool(json['domestic']) || isDomesticHost(host),
      sources: asStringList(json['sources']),
      firstSeen: asStringOr(json['firstSeen'], ''),
      checkedAt: asStringOr(json['checkedAt'], ''),
      settingImgHost: asStringOr(json['settingImgHost'], ''),
      appVersion: asStringOr(json['appVersion'], ''),
      detail: asStringOr(json['detail'], ''),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'host': host,
        'label': label,
        'status': status,
        'latencyMs': latencyMs,
        'httpStatus': httpStatus,
        'domestic': domestic,
        'sources': sources,
        'firstSeen': firstSeen,
        'checkedAt': checkedAt,
        if (settingImgHost.isNotEmpty) 'settingImgHost': settingImgHost,
        if (appVersion.isNotEmpty) 'appVersion': appVersion,
        if (detail.isNotEmpty) 'detail': detail,
      };
}
