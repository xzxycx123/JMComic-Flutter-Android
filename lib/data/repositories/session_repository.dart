import '../local/endpoint_store.dart';
import '../models/user_session.dart';
import '../sources/jm_api_client.dart';
import '../sources/jm_endpoint_resolver.dart';

/// cookie / 线路 / 版本状态（我的页「网络」一栏的数据源）。
class SessionRepository {
  SessionRepository({
    required JmApi api,
    required EndpointStore store,
    required JmEndpointResolver resolver,
  })  : _api = api,
        _store = store,
        _resolver = resolver;

  final JmApi _api;
  final EndpointStore _store;
  final JmEndpointResolver _resolver;

  UserSession get current => _api.session;

  /// 最近一次「发现 + 实测」报告。
  JmDiscoveryReport? get lastReport => _resolver.lastReport;

  /// 重新探测线路 + 刷新 /setting（强制重跑发现源与实测，清掉健康缓存）。
  Future<UserSession> rediscover() async {
    await _store.resetHealth();
    await _resolver.refresh(force: true);
    await _api.prepare();
    return _api.session;
  }

  /// 全量测速（设置页「线路测速」）：所有已知 API / 图床线路跑一遍。
  Future<JmDiscoveryReport> probeAll() => _resolver.probeAll();

  /// 当前健康表（UI 展示延迟 / 状态）。
  List<JmHostHealth> get apiHealth => _store.apiHealth;

  /// 手动指定域名（我的 -> 网络），保存后需要 [rediscover] 才生效。
  Future<void> setManualHost(String host) => _store.setManualHost(host);

  Future<void> clearDiscovered() => _store.clearDiscovered();

  String get manualHost => _store.manualHost;

  List<String> get apiHosts => _store.apiHosts;

  List<String> get imageHosts => _store.imageHosts;

  List<String> get webHosts => _store.webHosts;

  /// 单台线路的最近结论（没有记录返回 null）。
  JmHostHealth? healthOf(String host) => _store.healthOf(host);

  static String statusLabel(String status, {bool ok = false}) {
    if (ok) return '可用';
    return switch (status) {
      'timeout' => '超时',
      'tls_error' => 'TLS 失败',
      'cloudflare_challenge' => '人机校验',
      'not_json' => '非接口响应',
      'decrypt_failed' => '解密失败',
      'payload_unexpected' => '返回结构异常',
      'invalid_host' => '域名非法',
      'connection_error' => '连接失败',
      'cancelled' => '已取消',
      '' => '未测',
      _ when status.startsWith('http_') => 'HTTP ${status.substring(5)}',
      _ when status.startsWith('code_') => 'code ${status.substring(5)}',
      _ => status,
    };
  }
}
