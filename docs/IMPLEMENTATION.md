# 实施状态（M0–M6）

> 对应 `PLAN.md` 的里程碑。本文只记录「已经写成什么样」和「与 PLAN 的差异」，协议事实仍以 `PLAN.md` §5 与 `tools\probe_api.ps1` 的实时输出为准。

## 一、已落地的目录（82 个 Dart 源文件）

```
lib/
├─ main.dart                  Hive / SharedPreferences / DownloadHistory 初始化 + ProviderScope overrides
├─ app.dart                   MaterialApp.router + 主题注入
├─ core/
│  ├─ config/app_config.dart  并发 3 / 页 80 / 缓存 30min / 页边 14400 / LRU 12 ...
│  ├─ constants/              token、secret、UA、线路表、排序枚举、10 个顶层分类兜底
│  ├─ di/providers.dart       ★ 依赖注入唯一入口（api / 仓储 / store / sink / 通知）
│  ├─ theme/                  app_colors(两套显式 ColorScheme) + app_typography + app_theme
│  ├─ icons/                  app_icons.dart（SVG 常量 + SvgIcon）+ app_images.dart（品牌位图 + BrandMark / MascotLoading / BrandBanner）
│  ├─ router/app_router.dart  StatefulShellRoute 三 tab + /search /album/:id /reader
│  ├─ network/                dio_factory（HTTP/1.1 + cookie jar + JM_PROXY）+ 异常类型
│  ├─ image/                  image_scrambler（段数算法）+ image_processor（isolate 还原）
│  └─ utils/                  jm_id_parser / file_names / isolate_runner / logger
├─ data/
│  ├─ models/                 列表项、详情、章节、promote、分类、搜索页、下载记录、会话、HomeFeed
│  ├─ sources/                jm_crypto（AES-ECB 手写块处理）+ endpoint_resolver + api_client + parser + html_scraper
│  ├─ local/                  hive_init / endpoint_store / download_store（Hive + 内存双实现）/
│  │                          settings_store（含 provider）/ progress_store（进度 + 历史 + 收藏）
│  └─ repositories/           home / catalog / search / album / download / session
└─ features/
   ├─ shell/                  ShellPage + GlassNavBar（玻璃胶囊 Dock，首页/我的/下载）
   ├─ home/                   home_page + providers + 7 个 widget（轮播/分类条/排序条/分节/卡片/封面/骨架）
   ├─ album/                  album_page（模糊头 + 章节列表 + 双 CTA）+ providers + chapter_tile
   ├─ search/                 search_page（车号直达 / 关键词搜索）+ providers + 3 个 widget
   ├─ reader/                 reader_page（双模式 + 三分区 + HUD + 进度记忆）+ 4 个 widget
   ├─ mine/                   mine_page / settings_page / about_page
   └─ download/               download_page + providers + input/task 卡片 + engine/
      └─ engine/              task / slots / coordinator / worker / pdf_exporter / pdf_sink / notification
```

### 品牌素材接入（`img/` → `assets/images/`）

`tools/build_app_assets.py`（Python + Pillow）把 `img/` 的位图整理成 Flutter 资产，并派生 Android 桌面图标：

| 素材 | 用在哪 |
|---|---|
| `mascot/app_icon_512.png` | 桌面图标（`mipmap-*/ic_launcher.png` 48–192px）、启动屏居中位图、关于页图标 |
| `mascot/mark_*_256.png`（5 季） | AppBar 左侧方形头像、我的页头像；`AppImages.seasonalMark()` 按月份切换（1 新年 / 3–4 樱花 / 10 万圣 / 12 圣诞） |
| `brand/brand.png` | 关于页品牌横幅（容器是 WebP，脚本转真 PNG） |
| `loading/loading_cat_*_alpha.gif` | 详情页 / 章节加载中的黑猫动图 + 静态首帧兜底；阅读器深色底用白底小卡片承接 |
| `ui/icon_new|hot|day|week.png` | 卡片 NEW 角标（`adddate` 7 天内）、首页排序条（人气/日榜/周榜） |
| `ui/icon_rocket_280.png` | 下载页空态主图 |
| `ui/qr_app.png` | 关于页二维码卡片 |

图标位规则不变：交互图标仍全部来自 `assets/icons/*.svg`（`check_ui_rules.ps1` 仍通过）。
重新派生：`python tools/build_app_assets.py`（幂等）。


测试：`test/` 下 14 个用例文件、75 个用例 + `test/fixtures/` 8 个真实结构 fixture（含 `assets_test.dart` 素材守卫）。

## 二、与 PLAN 的差异（都为了「一次编译通过」而收敛）

| 项 | PLAN | 实际 | 原因 |
|---|---|---|---|
| PDF 落盘 | `media_store_plus` 首选，失败降级 app 目录 | `MethodChannel('jm_comic/pdf_store')` → `MainActivity.kt` 里用 MediaStore 写 `Documents/JMComics/`，失败降级 app 外部目录 + `open_filex` | 与 `JmScript/export/DocumentsPdfStore.kt` 行为逐行对齐，且不依赖插件版本漂移；`tools\apply_android_config.ps1` 负责注入 Kotlin |
| 通知 | `flutter_local_notifications` + `flutter_foreground_task` | 只用 `flutter_foreground_task`（通知文案随任务更新） | 少一个插件、少一套 Android 配置（core library desugaring） |
| 阅读器缩放 | `photo_view` | `InteractiveViewer` + 双击 1.0↔2.0 + 缩放时禁分区点击 | 行为与 §7.6 一致，少一个依赖 |
| 权限 | `permission_handler` | `FlutterForegroundTask.checkNotificationPermission/requestNotificationPermission` | 通知权限一个来源即可 |
| 依赖清单 | §3.1 的 20 项 | 去掉 `media_store_plus` / `flutter_local_notifications` / `photo_view` / `permission_handler`，其余版本下限不变 | 同上 |
| PDF 页尺寸 | 1px = 1pt、长边 14400 | 同（`PdfPageFormat(w, h, marginAll: 0)` + `pw.FullPage(ignoreMargins: true)`） | — |
| 首页缓存 | Hive + TTL 30min | 同（HomeFeed.encode() 存 Hive，冷启动先渲染缓存并标「缓存内容 · HH:mm 更新」，后台刷新） | — |
| 品牌位图 | §7.0：加载态不用 GIF/位图 | 首页 AppBar / 我的 / 关于用吉祥物位图；详情与阅读器加载用品牌黑猫 GIF（MascotLoading），骨架 shimmer 保留 | 用户明确要求把 img/ 素材用进 App；图标仍全部 SVG，check_ui_rules.ps1 通过 |
| compileSdk | §1：compileSdk = 35 | **36**（Flutter 3.50 插件默认按 36 编译） | 只用 35 会 plugin compiles against 36 校验失败 |

## 三、下载引擎对照（PLAN §8）

| Kotlin（JmScript） | Dart（本仓库） | 状态 |
|---|---|---|
| `JmApiClient.kt` | `data/sources/jm_api_client.dart` | 线路轮换 / cookie / 图床轮换 / HTML 视为失败 / `redirect series_id` 全部保留 |
| `JmCrypto.kt` | `data/sources/jm_crypto.dart` | token、AES-256-ECB（key = md5hex 的 32 个 ASCII 字节）、MIME Base64 容错；ECB 用 `AESEngine` 单块 + 手写 PKCS7，避开泛型坑 |
| `JmResponseParser.kt` | `data/sources/jm_response_parser.dart` | 章节升序去重、空 series 退化、空 images 抛 `JmContentException` |
| `ImageScrambler.kt` | `core/image/image_scrambler.dart` | 段数算法逐字对齐（含 `lastCodeUnit % modulus`） |
| `ImageProcessor.kt` | `core/image/image_processor.dart` | 倒序切片还原 + 真 PNG 重编码，跑在 `compute` isolate |
| `PdfExporter.kt` | `features/download/engine/pdf_exporter.dart` | 一页一图、页尺寸=位图尺寸、长边 14400、白底 |
| `DocumentsPdfStore.kt` | `pdf_sink.dart` + `MainActivity.kt` | `IS_PENDING` 先写后转正、同名 `(2)` |
| `DownloadSlots.kt` | `download_slots.dart` | 队列并发 3；另提供 `mapWithConcurrency`（单任务内 3 并发） |
| `DownloadCoordinator.kt` | `download_coordinator.dart` | 入队去重、取消、重试（IO ≤2 次）、清空已完成、僵尸 running 回收 |
| `JmDownloadWorker.kt` | `download_worker.dart` | 流水线 + 进度节流 + 失败页计数 + 临时目录必删 |
| `FileNames.kt` / `JmIdParser.kt` | `core/utils/*` | 码点截断、去重保序等语义一致 |
| WorkManager 前台任务 | `notification_service.dart` | `startService` + `updateService`，通知不可用时静默降级 |

## 四、验收自检结果（2026-11-15 本机实跑）

| 检查 | 命令 | 结果 |
|---|---|---|
| 依赖解析 | `flutter pub get` | ✅ 117 个包（mocktail 由 ^0.3.4 提到 ^1.0.5，其余按 PLAN 下限解析） |
| 静态检查 | `flutter analyze` | ✅ No issues found |
| 单元 + widget | `flutter test` | ✅ 78 个用例全绿（14 个文件；含素材守卫、到底分页、取消/失败页回归） |
| UI 守卫 | `tools\check_ui_rules.ps1` | ✅ 无 emoji、无 `Icons.*`、图标全 SVG |
| 素材派生 | `python tools\build_app_assets.py` | ✅ 24 个文件（assets/images 16 + mipmap 5 + 启动图 1 + 动图 2），≈0.54 MB（已按显示尺寸降采样） |
| Android 配置 | `tools\apply_android_config.ps1` | ✅ minSdk 29 / compileSdk 36 / targetSdk 35、权限、前台服务、MediaStore 通道 |
| 打包 | `flutter build apk --release` | ✅ `build\app\outputs\flutter-apk\app-release.apk`（universal，61.76 MB） |

APK 产物核对（`aapt2 dump badging` / `xmltree`）：

- 包名 `com.jmcomic.jm_comic`，`versionName 0.1.0`，`minSdk 29`，`targetSdk 35`，`compileSdk 36`
- `application-label: JMComic`（中英文资源同名）
- ABIs：`arm64-v8a` / `armeabi-v7a` / `x86_64`
- `MainActivity` 与 `com.pravera.flutter_foreground_task.service.ForegroundService`（`foregroundServiceType=dataSync`）均已注册
- 17 个品牌位图全部打进 `assets/flutter_assets/assets/images/`（合计 ≈1.7 MB）
- 已归档一份到 `dist\JMComic-0.1.0-release.apk`，SHA256 `3CB6FB84…C23E3DF`（审查修复后重打）

环境：Flutter 3.50.0（stable，`D:\data\tools\flutter`）、Dart 3.14.0、JDK 17.0.4（64 位）、
Android SDK platform 35 + 36、build-tools 35/36、AGP 9.3.1、Kotlin 2.4.20、Gradle 9.5.0。
关键依赖实际解析版本：`flutter_foreground_task 8.17.0`、`pdf 3.13.1`、`image 4.13.0`、`hive_ce 2.23.3`、
`go_router 14.8.1`、`flutter_svg 2.4.0`、`dio 5.11.1`、`flutter_riverpod 2.6.1`。

> 未做：真机安装跑 §2.2 清单、iOS 构建（v1 只验收 Android）。

## 四·补：品牌素材接入的审查记录

图片素材（`img/` → `assets/images/`）的映射表、引用完整性、体积/格式核对、深色主题与语义检查、
APK 打包验证，见 [REVIEW_brand-assets.md](REVIEW_brand-assets.md)。
## 五、编译期踩过的坑（已修，供复跑参考）

1. `image 4.x` 的 `compositeImage` 已改成两个位置参数：`compositeImage(dst, src, {dstY: ...})`。
2. `dio 5.x` 的 `IOHttpClientAdapter` 需要 `import 'package:dio/io.dart';`。
3. `flutter_foreground_task 8.17` 的 `TaskHandler` 必须实现 `onDestroy(DateTime timestamp)`（单参数）。
4. `http_mock_adapter` 默认按整条 URL 匹配：测试里用 `DioAdapter(dio: dio, matcher: const UrlRequestMatcher())` + `RegExp` 路由；`reply` 传 Map（传 String 会被二次 JSON 编码）。
5. widget 测试里 Hive 的异步写不会随 `pump` 推进，测试通过 override `homeRepositoryProvider`（不挂 cacheBox）绕开。
6. Flutter 3.50 把 `package:flutter/material.dart` 整体标记 deprecated（迁 `material_ui`），已在 analysis_options 里忽略该类提示。
7. 横滑分节卡原 232 高度在 2 行标题 + 大字号下会 RenderFlex 溢出：改为封面吃剩余空间（`Expanded`）+ 分节高 248，网格 `childAspectRatio` 0.54。
8. `workId` 只用微秒时间戳会在批量入队时碰撞（两任务共用临时目录，互相删页文件）：改为「时间戳 + 自增序号 + 随机后缀」。
9. Gradle/JVM：本机默认 `java` 是 **32 位** Liberica，`-Xmx8G/4G` 直接起不来；构建必须 `JAVA_HOME=C:\Program Files\Java\jdk-17.0.4`（64 位），并把 `org.gradle.jvmargs` 降到 4G。
10. Flutter 3.50 插件默认 `compileSdk 36`，工程只写 35 会触发 `plugin compiles against 36` 校验失败：已装 `platforms;android-36` 并把 compileSdk 提到 36（minSdk 29 / targetSdk 35 不变）。
11. Maven Central 直连会 `Remote host terminated the handshake`：`~/.gradle/gradle.properties` 里走本机代理 127.0.0.1:7890（本机文件，不入库）。
12. Kotlin 2.4 在「pub cache 在 C: / 工程在 D:」时增量编译报 `this and base files have different roots`：`android/gradle.properties` 设 `kotlin.incremental=false`。
13. Gradle 9.5 的 build-logic 锁会被残留 daemon 占住（`Timeout waiting to lock build logic queue`）：打包前先 `Get-Process java | Stop-Process` 并删 `android/.gradle/noVersion`。
14. 应用展示名：`AndroidManifest.xml` 的 `android:label` 与 iOS `CFBundleDisplayName` 都改成 `JMComic`。

## 六、网络模块重写（2026-11-15）

现象是「连通性检测有问题」，实际是协议层 + 发现层 + 重试策略三处叠加：

1. **AES key 被截断成 16 字节**：真实协议是 AES-256-ECB，key = `ASCII(md5hex(ts+secret))` 的 32 字节。
   截断后每条线路都「HTTP 200 但解密失败」，看起来就是全线路不可用。修在 `jm_crypto.dart`，
   `test/data/jm_crypto_test.dart` 用 .NET 侧密文 + 真实 `/setting` 采样（`test/fixtures/setting_envelope_live.json`）锁死。
2. **域名发现只读 `Server`**：补上 `Setting` / `jm3_Server`（带线路标签与第 5 条线路），
   并新增发布页（国内域名）与 GitHub 镜像两个旁路源。
3. **没有真探测**：新增 `jm_host_probe.dart`，`/setting` 全链路（token + 解密 + `jm3_version`/`img_host`）
   才算 ok；新增 `jm_host_catalog.dart` 统一解析四类源。
4. **串行重试**：改为「健康度排序 + 10 分钟冷却 + 单次尝试 9s」，冷启动只在没有任何新鲜 ok 线路时才跑
   首批 4 台探测（5s/台，有 ok 即停）。
5. **国内地址**：`comic18j-susu.com` / `comic18j-nico.work` / `comic18j-neo.com` 不提供 APP 接口，
   但 `/media/...` 能直出图片，已作为国内图床兜底；同时「自动切换线路」开关真正接上了。
6. 产物：`assets/data/jm_hosts.json`（内置种子，7 条 API / 25 条图床 / 7 个网页域名，含延迟与时间戳）、
   `tools/probe_hosts.ps1`（重新生成种子与报告）、`docs/NETWORK_MODULE.md`（设计与排障）。

测试：111 个用例全绿（新增 crypto/catalog/probe/store/resolver/rotation 六组，含实网 skip 用例）。
## 七、构建环境恢复与重打 APK（2026-11-15）

接手时本机 Android SDK 组件全丢（`flutter doctor` 报 `cmdline-tools component is missing`，`$SDK` 目录为空），
`flutter build apk` 直接失败。恢复步骤（可照抄）：

```powershell
$sdk = 'C:\Users\Jolie\AppData\Local\Android\Sdk'
# 1) cmdline-tools（只需一次）：解压后放到 $sdk\cmdline-tools\latest
curl -L --proxy http://127.0.0.1:7890 -o "$env:TEMP\clt.zip" `
  https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip
tar -xf "$env:TEMP\clt.zip" -C "$env:TEMP\clt"
# 2) platform / build-tools / NDK 直接取官方 zip（新版 Android CLI 不认 "pkg;ver" 语法）
#    platform-36_r02.zip        -> $sdk\platforms\android-36
#    build-tools_r36_windows.zip-> $sdk\build-tools\36.0.0   （zip 内目录叫 android-16，需改名）
#    android-ndk-r28c-windows.zip -> $sdk\ndk\28.2.13676358  （zip 内目录叫 android-ndk-r28c）
```

要点：

1. **NDK 是硬需求**：`jni 1.1.2`（transitive，来自 `jni_flutter`）带 CMake 原生构建；
   缺 NDK 时 Gradle 报 `Could not find toolchain file: $SDK\ndk\28.2.13676358\build\cmake\android.toolchain.cmake`。
2. **不能靠 Flutter 自动 provision**：它执行 `sdkmanager --install "ndk;28.2.13676358"`，
   而 cmdline-tools 23 的新版 Android CLI 把 `;` 当分隔符，报 `Package ndk not found` / `Package 28.2.13676358 not found`；
   必须手工放置 NDK（或用旧版 sdkmanager 23.0.0 以下）。
3. 构建命令（JAVA_HOME 必须是 64 位 JDK 17）：

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.4'
$env:Path = 'D:\data\tools\flutter\bin;' + $env:JAVA_HOME + '\bin;' + $env:Path
Get-Process java -ErrorAction SilentlyContinue | Stop-Process -Force   # 清残留 daemon 锁
flutter build apk --release
```

4. 本次产物：`build\app\outputs\flutter-apk\app-release.apk` **61.97 MB**，
   `dist\JMComic-0.1.0-release.apk`，SHA256 `D0A321B3…D9DAFB6B`；
   badging 核对：`com.jmcomic.jm_comic` / 0.1.0 / minSdk 29 / targetSdk 35 / compileSdk 36 /
   `JMComic` / ABIs `arm64-v8a,armeabi-v7a,x86_64`；
   APK 内 `assets/flutter_assets/assets/images/` 17 个位图 + `assets/data/jm_hosts.json` 均在。
5. `.gitignore` 补齐非必须文件：`img/*.psd`、`img/未标题-*.png`（设计草稿）、`dist/`、`*.apk/*.aab`、
   `.dart_tool/`、`build/`、`.idea/`、`*.iml`、`android/.gradle|cxx|kotlin`、`__pycache__`、`*.log` 等。

## 七、阅读器加载与分流切换（2026-11-15）

1. **加载 bug**：旧 `_loadPage` 在并发满 2 时直接 `return`，被拒的页没有队列也没有重试，于是进入阅读器只会加载 2 页，其余一直转圈。
2. **修复**：新增 `lib/features/reader/reader_page_loader.dart` —— 窗口 `焦点-2 .. 焦点+5`、并发 3、前向优先、槽位空出自动补位、失败可重试、LRU 14 页、`clear/dispose` 用 generation 作废旧请求；`reader_page.dart` 全面接入（删掉旧的 `_pageBytes/_loading/_failed/_preloadAround`）。
3. **分流切换**：`JmApi` 新增 `availableHosts` / `switchApiHost(host)`；`JmApiClient.switchApiHost` 只请求目标线路 `/setting`，成功后更新图床（`img_host`）、写健康表并置顶持久化，失败保留原线路。`JmConstants.lineLabels` 收录线路1-5（`www.cdnbtd.cc` / `www.cdnutc.cc` / `www.cdngwc.net` / `www.cdngwc.club` / `www.cdnutc.me`）。
4. **UI**：`ReaderHud` 顶栏「线路N」按钮 -> 底部弹层（当前置顶 / 标签 / 主机 / 最近延迟）；切换后清空阅读缓存并按当前页重载，图床跟着换。
5. **验证**：`flutter analyze` 无问题；`flutter test` 123 通过 / 2 skip（新增 loader 7 个、HUD 分流 2 个、分流切换 3 个用例）。
## 八、v0.1.2 变更（2026-11-15）

1. **启动行为**：打开 App 先用「上次成功线路 + 上次首页缓存」秒开，再后台拉新并整体替换。
   - `EndpointStore` 新增 `jm_last_api_host`（`lastApiHost`），成功一次即持久化；`apiHosts` 排序把手填线路排第一、`lastApiHost` 紧随其后。
   - `JmEndpointResolver._fastPath()`：上次线路的健康记录仍在 30 分钟 TTL 内时，**零网络**复用（跳过四源发现 + 探测）；`probeAll()`/设置页「重新探测」仍走全量。
   - `HomeFeedNotifier.build()` 改为「先读 Hive 缓存（不看 TTL、不等 `jmBootstrapProvider`）→ 立即返回 → 后台刷新后 `state = data(fresh)` 替换」；首页顶部条显示「上次内容 · HH:mm · 正在更新」。
   - 失败兜底：后台刷新失败保持缓存内容；只有无缓存且首拉失败才进整页错误态。
2. **Dock 由三档改两档**：`首页 / 我的`；`/download`、`/history` 改为顶层 push 路由，从「我的 → 下载与历史」进入（返回即回我的）。
3. **新增历史记录页** `features/download/history_page.dart`：全部 / 已完成 / 失败 / 已取消 四档筛选、打开 PDF、重试、删除、清空已完成；「我的」里显示进行中数量与历史条数。
4. **版本与许可**：`pubspec.yaml` → `0.1.2+2`（versionCode 2），`AppConfig.appVersion = '0.1.2'`；新增仓库根 `LICENSE`（MIT，Copyright (c) 2026 xzxycx）与 `lib/core/constants/license_text.dart`；关于页新增「开源许可（MIT License）」弹窗与版权行，「第三方开源许可」仍走 `showLicensePage`。
5. **验证**：`flutter analyze` 无问题；`flutter test` **128 通过 / 2 跳过**（新增 history、dock 两档、缓存读取用例）；UI 守卫通过。
6. **产物**：`dist\JMComic-0.1.2-release.apk`，62.08 MB，SHA256 `237C529B…FB87E601`，
   `versionName 0.1.2 / versionCode 2 / minSdk 29 / targetSdk 35 / compileSdk 36`。

## 九、v0.2.0 变更（2026-11-15）

1. **登录 + 收藏（M4.5）**：新增 `AccountSession` / `SessionStore`（`jm_session`）/ `AuthRepository`、
   `FavoriteItem` / `FavoritesStore`（per-album 账本 + 文件夹 + outbox）/ `FavoritesRepository`（对账 + toggle 反向自愈）、
   `/login` 与 `/collect` 两个页面；详情页收藏改为乐观更新 + 撤销，并清理「有更新」角标。
   - 协议：`GET /favorite?page&o&folder_id`、`POST /favorite {aid}`（toggle，核对 `type`）、`POST /login`（multipart，带 `s` 时补 `AVS` cookie）。
   - 红线：不存明文密码；写本地读本地；服务端只镜像布尔；登出清 session/cookie/outbox 并把收藏降级为「仅本地」。
   - 迁移：老 `jm_favorites = {ids:[…]}` 启动时迁成 per-album 记录（幂等）。
2. **许可证改为 GPL-3.0**：仓库根 `LICENSE` 与 `assets/licenses/GPL-3.0.txt` 为 GNU GPL v3 全文，
   关于页从 asset 读取并展示；版权行 `Copyright (C) 2026 xzxycx`。
3. **阅读器 HUD 避开系统状态栏**：`ReaderHud` 顶部条改为 `SafeArea(bottom: false)` 包内容、底色铺到状态栏下方，
   不再与时间/信号图标重叠。
4. **版本 0.2.0**：`pubspec.yaml` → `0.2.0+3`（versionCode 3），`AppConfig.appVersion = '0.2.0'`。
5. **验证**：`flutter analyze` 无问题；`flutter test` **139 通过 / 2 跳过**（新增 `favorites_test` 11 条：迁移、outbox 去重、本地/在线 toggle、对账、反向自愈、登录/登出/会话恢复）；UI 守卫通过。
6. **产物**：`dist\JMComic-0.2.0-release.apk`，62.49 MB，SHA256 `3BADD35B…01BC10E`，
   `versionName 0.2.0 / versionCode 3 / minSdk 29 / targetSdk 35 / compileSdk 36`。
