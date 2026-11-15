import '../constants/jm_constants.dart';

/// 域名归一化 / 归属判断（线路表、健康记录、图床都靠它做去重）。
///
/// 只接受「主机名」这一种形态：协议、路径、端口、前后空白全部丢掉，
/// 非法输入返回 null（调用方负责过滤，不要静默塞一个空串进线路表）。

final RegExp _hostPattern =
    RegExp(r'^[a-z0-9][a-z0-9\-\.]{1,80}\.[a-z]{2,24}$');

String? normalizeHost(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final withScheme =
      value.toLowerCase().startsWith('http') ? value : 'https://$value';
  final uri = Uri.tryParse(withScheme);
  final host = (uri?.host ?? '').toLowerCase();
  if (host.isEmpty) return null;
  if (!host.contains('.')) return null;
  if (!_hostPattern.hasMatch(host)) return null;
  return host;
}

/// `https://cdn.example.com/x.jpg` -> `cdn.example.com`；非法返回 null。
String? hostFromUrl(String? raw) => raw == null ? null : normalizeHost(raw);

/// 国内线路判定：发布页「內地 / 分流」栏的域名，或显式带 comic18j 前缀的镜像。
bool isDomesticHost(String host) {
  final normalized = normalizeHost(host);
  if (normalized == null) return false;
  if (JmConstants.domesticHosts.contains(normalized)) return true;
  return normalized.contains('comic18j');
}
