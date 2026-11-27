# 网络模块

## 传输、线路和协议

| 负责方 | 职责 | 入口 |
| --- | --- | --- |
| Dio 工厂 | 配置 `dart:io` 适配器、超时、代理选项、重定向和 Cookie 拦截器。业务 Dio 绑定进程内 `JmCookieJar`，探测 Dio 采用较短超时并独立创建 | [`dio_factory.dart`](../../../lib/core/network/dio_factory.dart) · [`providers.dart`](../../../lib/core/di/providers.dart) |
| 线路目录 `JmHostCatalog` | 解析种子和发现来源，归类并合并 API、图片、网页候选 | [`jm_host_catalog.dart`](../../../lib/data/sources/jm_host_catalog.dart) |
| 线路探测 `JmHostProbe` | 校验候选线路的实际响应，返回可用性、失败分类、延迟等结果。解析线路结果时区分 HTTP 状态和响应内容 | [`jm_host_probe.dart`](../../../lib/data/sources/jm_host_probe.dart) |
| 发现编排 `JmEndpointResolver` | 合并候选、复用近期报告和进行中的刷新，按健康记录走启动快路径或分批探测。全量测速单独扫描 API 和图片线路 | [`jm_endpoint_resolver.dart`](../../../lib/data/sources/jm_endpoint_resolver.dart) |
| 线路状态 `EndpointStore` | 在 SharedPreferences 维护候选、手动设置、最近成功线路、健康与冷却记录及协议版本 | [`endpoint_store.dart`](../../../lib/data/local/endpoint_store.dart) |
| 协议客户端 `JmApiClient` | 实现 `JmApi`，负责准备阶段、请求封装、线路选择、失败分类、健康回写和图片字节读取 | [`jm_api_client.dart`](../../../lib/data/sources/jm_api_client.dart) |
| 协议工具与模型映射 | `JmCrypto` 负责签名和响应解密，`JmResponseParser` 负责把业务载荷转成模型，字段兼容读取工具在 `json_field.dart` | [`jm_crypto.dart`](../../../lib/data/sources/jm_crypto.dart) · [`jm_response_parser.dart`](../../../lib/data/sources/jm_response_parser.dart) · [`json_field.dart`](../../../lib/data/models/json_field.dart) |
| 设置页入口 `SessionRepository` | 给设置页提供线路状态和错误文案，接收手动配置、强制重发现和全量测速请求 | [`session_repository.dart`](../../../lib/data/repositories/session_repository.dart) · [`settings_page.dart`](../../../lib/features/mine/settings_page.dart) |

## 业务请求与会话

1. **准备。** `jmBootstrapProvider` 等待 `JmApi.prepare()`。客户端先调用 resolver 刷新线路，再处理 `/setting` 的 Cookie、图片线路和协议版本。首页可在 bootstrap 完成前通过 Hive 读出默认 Feed 缓存。相关入口见 [`providers.dart`](../../../lib/core/di/providers.dart) 和 [`home_providers.dart`](../../../lib/features/home/home_providers.dart)。
2. **线路选择。** `EndpointStore` 提供候选，`JmApiClient` 根据自动切换设置、手动线路、冷却状态和最近成功线路选择顺序。普通请求在单次尝试和整体预算下执行，整体预算在尝试之间检查。显式 `switchApiHost` 只验证选中的目标，验证成功后切换。相关入口见 [`jm_api_client.dart`](../../../lib/data/sources/jm_api_client.dart)。
3. **失败归类。** 传输或协议封包失败按 `JmApiException` 处理，客户端据此记录线路失败并尝试候选。业务错误走 `JmContentException`，例如 HTTP 401、429 或服务端业务错误码，线路仍记作可用，异常直接交回调用者。下载任务的主动取消走 `JmCancelledException`。相关入口见 [`api_exception.dart`](../../../lib/core/network/api_exception.dart) 和 [`jm_api_client.dart`](../../../lib/data/sources/jm_api_client.dart)。
4. **会话存续。** `JmCookieJar` 保存内存中的 Cookie，客户端把响应后更新的快照通过回调交给 `SessionStore` 持久化，普通响应有节流。`AuthRepository` 按需恢复旧快照，准备就绪后验证账号；恢复路径在确认会话失效时尝试一次凭据重登。`CredentialVault` 管理系统密钥库存取。`UserSession` 是线路和协议快照，账号登录态看 `AccountSession` / `accountSessionProvider`。相关入口见 [`auth_repository.dart`](../../../lib/data/repositories/auth_repository.dart)、[`session_store.dart`](../../../lib/data/local/session_store.dart) 和 [`collect_providers.dart`](../../../lib/features/collect/collect_providers.dart)。

## 图片、首页兜底与更新

| 链路 | 职责与排查入口 |
| --- | --- |
| 封面 | `CoverImage` 等待 bootstrap，取 `JmApi` 提供的 URL 和头部交给 Flutter `NetworkImage`。封面异常先查组件和图片线路。见 [`cover_image.dart`](../../../lib/features/home/widgets/cover_image.dart)。 |
| 阅读与下载图片 | `JmApiClient.downloadImage()` 用业务 Dio 取字节，按图片线路处理 HTML、空响应与健康回写。阅读器和下载 Worker 调用 `core/image/` 的公共图像处理逻辑。图片请求成功但解码或显示异常时，接着检查 `AlbumRepository.loadPage()` 与 `ReaderPageLoader`，或对应导出 Worker。见 [`album_repository.dart`](../../../lib/data/repositories/album_repository.dart)、[`reader_page_loader.dart`](../../../lib/features/reader/reader_page_loader.dart) 和 [图片处理目录](../../../lib/core/image/)。 |
| 首页降级 | `HomeRepository` 聚合多个业务接口并保留部分错误。主要内容为空时走 DI 提供的 HTML 回调，由 `JmHtmlScraper` 解析首页，允许在对应策略下回退到已有缓存。见 [`home_repository.dart`](../../../lib/data/repositories/home_repository.dart) 和 [`jm_html_scraper.dart`](../../../lib/data/sources/jm_html_scraper.dart)。 |
| 应用更新 | `releaseDioProvider` 独立于业务 Cookie 与线路切换。`GithubReleaseClient` 优先取 Release API，失败时读取 Atom。`UpdateRepository` 负责按版本找 APK、下载和调用 `AppPlatformChannel` 唤起 Android 安装。见 [`providers.dart`](../../../lib/core/di/providers.dart)、[`github_release_client.dart`](../../../lib/data/sources/github_release_client.dart) 和 [`update_repository.dart`](../../../lib/data/repositories/update_repository.dart)。 |

## 验证入口

- 线路发现、归类、健康与冷却。用 `flutter test test/data/jm_host_catalog_test.dart test/data/jm_host_probe_test.dart test/data/jm_endpoint_resolver_test.dart test/data/endpoint_store_test.dart`。
- API 线路轮换、业务错误、解包与模型映射。用 `flutter test test/data/jm_api_client_rotation_test.dart test/data/jm_api_client_test.dart test/data/jm_crypto_test.dart test/data/jm_response_parser_test.dart`。轮换用例复用可按 host 分流的 stub adapter。
- 账号、收藏与签到。用 `flutter test test/features/favorites_test.dart test/features/interaction_test.dart test/features/check_in_test.dart`。检查账号状态、Cookie 恢复、离线出队和签到缓存时按对应 Provider 注入替身。
- 封面以外的图片处理、阅读加载、首页降级与更新。用 `flutter test test/download/image_processor_test.dart test/features/reader_loader_test.dart test/data/jm_html_scraper_test.dart test/features/home_repository_test.dart test/data/github_release_client_test.dart test/features/update_gate_test.dart test/features/update_dialog_test.dart`。
- 普通验证使用仓库内的 mock、fixture 和临时 Store。`test/manual/` 中的实网用例默认跳过，线路历史说明以文档记录时的实现和环境为背景。
