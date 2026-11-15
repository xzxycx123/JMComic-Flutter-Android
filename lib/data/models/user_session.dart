import 'json_field.dart';

/// 线路与会话状态（我的页「网络」一栏 + 封面 URL 拼接用）。
class UserSession {
  const UserSession({
    this.apiHost = '',
    this.imageHost = '',
    this.appVersion = '',
    this.cookieCount = 0,
    this.manualHost = '',
    this.updatedAt = 0,
    this.ready = false,
    this.message = '',
  });

  final String apiHost;
  final String imageHost;
  final String appVersion;
  final int cookieCount;

  /// 用户手填的线路（我的 -> 网络 -> 手动填域名），优先于自动发现。
  final String manualHost;
  final int updatedAt;
  final bool ready;
  final String message;

  String get apiBase => apiHost.isEmpty ? '' : 'https://$apiHost';

  String get displayImageHost {
    if (imageHost.isEmpty) return '未获取';
    return imageHost.replaceFirst(RegExp(r'^https?://'), '').replaceAll('/', '');
  }

  UserSession copyWith({
    String? apiHost,
    String? imageHost,
    String? appVersion,
    int? cookieCount,
    String? manualHost,
    int? updatedAt,
    bool? ready,
    String? message,
  }) =>
      UserSession(
        apiHost: apiHost ?? this.apiHost,
        imageHost: imageHost ?? this.imageHost,
        appVersion: appVersion ?? this.appVersion,
        cookieCount: cookieCount ?? this.cookieCount,
        manualHost: manualHost ?? this.manualHost,
        updatedAt: updatedAt ?? this.updatedAt,
        ready: ready ?? this.ready,
        message: message ?? this.message,
      );

  factory UserSession.fromJson(Map<String, dynamic> json) => UserSession(
        apiHost: asStringOr(json['apiHost'], ''),
        imageHost: asStringOr(json['imageHost'], ''),
        appVersion: asStringOr(json['appVersion'], ''),
        cookieCount: asInt(json['cookieCount']),
        manualHost: asStringOr(json['manualHost'], ''),
        updatedAt: asInt(json['updatedAt']),
        ready: asBool(json['ready']),
        message: asStringOr(json['message'], ''),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'apiHost': apiHost,
        'imageHost': imageHost,
        'appVersion': appVersion,
        'cookieCount': cookieCount,
        'manualHost': manualHost,
        'updatedAt': updatedAt,
        'ready': ready,
        'message': message,
      };
}
