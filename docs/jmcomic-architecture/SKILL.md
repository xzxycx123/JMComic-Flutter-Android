---
name: jmcomic-architecture
description: 梳理和维护 JMComic Flutter 仓库。用于分析项目结构、定位页面与 Provider、划分数据层和平台层职责，或排查启动、网络、会话、缓存、阅读、下载和应用更新问题。
---

# JMComic 项目结构与维护

以当前源码和定向测试为准。先按任务定位负责的模块，再沿入口追到对应 Provider、仓储、数据源或存储。涉及 Dio、线路健康、会话恢复、图片请求或 GitHub 更新时，读[网络模块参考](references/network.md)。

## 启动与分层

| 板块 | 职责 | 入口 |
| --- | --- | --- |
| 启动 | 初始化 Flutter、LiquidGlass 和 Hive，迁移旧收藏，恢复下载历史并把中断任务标为失败，向 `ProviderScope` 注入启动依赖 | [`main.dart`](../../lib/main.dart) |
| 应用与路由 | 根应用读取主题与界面风格并触发账号恢复。`GoRouter` 管理首页和「我的」两个常驻分支、搜索、详情、阅读及其他子页面 | [`app.dart`](../../lib/app.dart) · [`app_router.dart`](../../lib/core/router/app_router.dart) |
| `lib/core/` | DI 组装、路由、配置、HTTP 工厂与公共异常、主题、通用组件、图片处理和工具函数 | [`providers.dart`](../../lib/core/di/providers.dart) · [`app_config.dart`](../../lib/core/config/app_config.dart) |
| `lib/data/sources/` | 对接外部协议或平台能力。负责 HTTP、响应解析、端点探测、发布信息与平台通道 | [数据源目录](../../lib/data/sources/) |
| `lib/data/models/` | 定义各层传递的数据结构和 JSON 字段转换 | [模型目录](../../lib/data/models/) |
| `lib/data/repositories/` | 编排取数、聚合、缓存、同步和任务入口，向调用方提供业务操作 | [仓储目录](../../lib/data/repositories/) |
| `lib/data/local/` | 管理落盘格式与迁移。Hive 保存应用设置、收藏、搜索与阅读历史、下载记录、签到快照和账号会话。SharedPreferences 保存线路状态。系统密钥库保存用户选择记住的凭据 | [`hive_init.dart`](../../lib/data/local/hive_init.dart) · [`settings_store.dart`](../../lib/data/local/settings_store.dart) · [`endpoint_store.dart`](../../lib/data/local/endpoint_store.dart) · [`credential_store.dart`](../../lib/data/local/credential_store.dart) |
| `lib/features/` | 页面、业务组件和 Riverpod 状态。独立运行的下载编排放在 `features/download/engine/` | [功能目录](../../lib/features/) |

常见依赖链是页面 → 功能 Provider / Notifier → Repository → 数据源或 Store。共享依赖见 `core/di/providers.dart`，账号和收藏的 Provider 见 `collect_providers.dart`。设置状态在 `settings_store.dart`，签到 Provider 直接使用 `JmApi` 和 `CheckInStore`，下载仓储通过懒加载的 API 依赖连接下载引擎。追踪问题时以实际引用为准。

## 功能分工与修改入口

| 板块 | 职责与边界 | 入口 |
| --- | --- | --- |
| `shell` | 底部导航、分支栈、设置页收起导航栏，挂载启动更新检查 | [`shell_page.dart`](../../lib/features/shell/shell_page.dart) |
| `home` | 首页分区、分类和排序、分页、内存缓存与预热。仓储负责聚合、默认页磁盘缓存和 HTML 降级。分类请求使用 slug | [`home_providers.dart`](../../lib/features/home/home_providers.dart) · [`home_repository.dart`](../../lib/data/repositories/home_repository.dart) · [`catalog_repository.dart`](../../lib/data/repositories/catalog_repository.dart) |
| `search` | 查询识别、排序、分页、本地历史与结果元数据补全。搜索路由创建独立的 ProviderScope | [`search_providers.dart`](../../lib/features/search/search_providers.dart) · [`search_repository.dart`](../../lib/data/repositories/search_repository.dart) |
| `album` | 详情、章节、点赞、评论分页、评论过滤与继续阅读入口。共享的章节和单页数据由仓储提供 | [`album_providers.dart`](../../lib/features/album/album_providers.dart) · [`comment_filter.dart`](../../lib/features/album/comment_filter.dart) · [`album_repository.dart`](../../lib/data/repositories/album_repository.dart) |
| `reader` | 在线阅读状态、滚动和翻页、预取、内存缓存与阅读进度。页面调度在 `ReaderPageLoader`，进度由 `ProgressRecorder` 写入 `ProgressStore` | [`reader_providers.dart`](../../lib/features/reader/reader_providers.dart) · [`reader_page_loader.dart`](../../lib/features/reader/reader_page_loader.dart) · [`progress_store.dart`](../../lib/data/local/progress_store.dart) |
| `download` | 下载与历史界面由 Provider 订阅任务记录。`DownloadRepository` 提交任务，`DownloadCoordinator` 管理并发、取消和重试，Worker 处理普通下载或阅读器导出，`PdfExporter` 和 `PdfSink` 分别负责生成和落盘 | [`download_repository.dart`](../../lib/data/repositories/download_repository.dart) · [下载引擎](../../lib/features/download/engine/) |
| `pdf` | 打开本地 PDF、渲染页面并管理文档生命周期。Flutter 页面通过 `PdfReader` 对接 Android `PdfRenderer`，与在线阅读共享部分控件 | [`pdf_viewer_page.dart`](../../lib/features/pdf/pdf_viewer_page.dart) · [`pdf_reader_channel.dart`](../../lib/data/sources/pdf_reader_channel.dart) |
| `auth` / `collect` | `auth` 提供登录界面，`AuthRepository` 管理登录、恢复和退出，`collect` 持有账号与收藏状态。收藏先写本地，仓储负责远端对账及待同步队列，`favorites_sync.dart` 负责同步状态 | [`login_page.dart`](../../lib/features/auth/login_page.dart) · [`collect_providers.dart`](../../lib/features/collect/collect_providers.dart) · [`auth_repository.dart`](../../lib/data/repositories/auth_repository.dart) · [`favorites_repository.dart`](../../lib/data/repositories/favorites_repository.dart) · [`favorites_sync.dart`](../../lib/features/collect/favorites_sync.dart) |
| `mine` | 账号与设置入口、线路管理、阅读历史、关于、签到。`CheckInNotifier` 负责服务端签到和刷新，`CheckInStore` 按账号缓存月历快照 | [`settings_page.dart`](../../lib/features/mine/settings_page.dart) · [`read_history_page.dart`](../../lib/features/mine/read_history_page.dart) · [`check_in_providers.dart`](../../lib/features/mine/check_in_providers.dart) · [`check_in_store.dart`](../../lib/data/local/check_in_store.dart) |
| `update` | 启动和设置页的更新状态、发布说明、下载及安装交互。仓储负责版本比较、APK 下载和调用平台能力 | [`update_providers.dart`](../../lib/features/update/update_providers.dart) · [`update_repository.dart`](../../lib/data/repositories/update_repository.dart) |

## 平台、资源与工具

- `android/` 管理 Gradle、权限、原生实现和 APK 构建。公共目录写入、PDF 渲染、应用信息和安装相关能力在 `MainActivity.kt`。改平台功能时成对检查 Dart 通道和对应 Kotlin 分支。`ios/` 保留 Runner，`web/`、`windows/` 是 `.gitignore` 排除的本地目录。Gradle 是 Android SDK 配置的依据。相关入口见 [`build.gradle.kts`](../../android/app/build.gradle.kts)、[`AndroidManifest.xml`](../../android/app/src/main/AndroidManifest.xml) 和 [`MainActivity.kt`](../../android/app/src/main/kotlin/com/jmcomic/jm_comic/MainActivity.kt)。
- `core/theme/` 和 `core/ui/` 管理主题、界面风格及共享组件。界面修改优先复用 `App*` 控件，检查 Metal 和 LiquidGlass 两种风格。图标经 `AppIcons`、`SvgIcon` 引用 `assets/icons/`。`assets/` 是 `pubspec.yaml` 声明的运行资源，`img/` 存放品牌素材，`ref img/` 存放参考截图。相关入口见 [主题目录](../../lib/core/theme/)、[公共 UI 目录](../../lib/core/ui/)、[`pubspec.yaml`](../../pubspec.yaml) 和 [`tools/build_app_assets.py`](../../tools/build_app_assets.py)。
- `test/` 存放单元、Widget 和流程测试，`test/fixtures/` 存放测试样本。`tool/` 与 `tools/` 存放开发脚本。`docs/` 与 `Plan/` 保存设计和实施记录。`build/` 与 `dist/` 是构建和归档目录。`dsh-subagent-models/` 是仓库内单独的 JavaScript 包，入口与依赖见其 [`package.json`](../../dsh-subagent-models/package.json)。

## 修改后的定向验证

在仓库根目录运行对应的本地测试。Widget 测试可覆盖 Provider 注入依赖，涉及存储时复用临时 Hive 与模拟 SharedPreferences 的[测试环境](../../test/helpers/test_env.dart)。

| 变更 | 建议验证 |
| --- | --- |
| 启动、路由与主题 | `flutter test test/features/shell_page_test.dart test/features/interface_style_selector_test.dart` |
| 首页和搜索 | `flutter test test/features/home_repository_test.dart test/features/home test/features/search_flow_test.dart test/features/search` |
| 详情、交互与签到 | `flutter test test/features/album_page_test.dart test/features/interaction_test.dart test/features/check_in_test.dart` |
| 在线阅读、进度和 PDF | `flutter test test/features/reader_test.dart test/features/reader_loader_test.dart test/features/reader_progress_test.dart test/features/pdf_reader_hud_test.dart` |
| 下载和阅读器导出 | `flutter test test/download` |
| 收藏、会话、线路和更新 | 按[网络模块参考的验证入口](references/network.md#验证入口)选择 |
| 通用 UI 和图标 | `flutter test test/core/ui/glass test/features/ui_rules_test.dart`，并在 PowerShell 运行 `pwsh -File tools/check_ui_rules.ps1` |

跨层代码变更可运行 `flutter analyze` 和 `flutter test`。修改 Hive 记录、偏好键或平台通道时，定向检查旧记录读取、启动迁移以及 Dart 与 Kotlin 的参数和返回值。
