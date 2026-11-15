# JMComic Flutter 客户端 · 施工方案（交接文档）

> 目标读者：接手的 AI / 工程师。本文档自包含，按 §9 的里程碑顺序照做即可产出可安装的 App。
> 工程根目录：`D:\data\product\JMComic`　基准参考项目（只读，勿改）：`D:\data\coding\JmScript`
> 文档内所有协议事实均来自 2026-11-14 本机实网探测（脚本：`tools\probe_api.ps1`），非猜测。

---

## 0. 一句话目标

用 Flutter 做一个 Android 优先的 JMComic 客户端：**首页靠移动端 API 抓取真实内容**，底部 Dock 三档「首页 / 我的 / 下载」，**下载模块按 `JmScript` 的 Kotlin 实现 1:1 移植成 Dart 引擎**（批量车号 → 切片还原 → PNG → PDF → `Documents/JMComics/`），UI 走现代 Material 3。

---

## 1. 现状与约束（已勘测）

| 项 | 实测结果 | 影响 |
|---|---|---|
| 工作目录 `D:\data\product\JMComic` | 空目录（本轮已建目录骨架） | 直接作为 Flutter 工程根 |
| Flutter SDK | **未安装** | M0 必须先装，见 §9 M0 |
| Dart | 随 Flutter 提供 | 同上 |
| Android SDK | `C:\Users\Jolie\AppData\Local\Android\Sdk`，platforms 仅 android-35，build-tools 34/35，cmdline-tools/latest | `compileSdk/targetSdk = 35`、`minSdk = 29` |
| JDK | Liberica 17（`C:\Program Files (x86)\BellSoft\LibericaJRE-17-Full`） | 满足 AGP 要求 |
| Git | `E:\Git\cmd\git.exe` | 用于拉 Flutter SDK |
| 磁盘 | D 盘剩余 124 GB | 充足 |
| 参考项目 `D:\data\coding\JmScript` | Kotlin + Gradle Android app（`com.jmscript.pdf`，minSdk 29，WorkManager + OkHttp + Gson），含完整单元测试 | 作为**行为基准 + 测试向量来源**，只读 |

---

## 2. 交付物与验收（DoD）

### 2.1 交付物

1. 可编译 Flutter 工程（`lib/` 全量实现、`android/` 配置就绪）。
2. `tools\scaffold.ps1`（幂等目录脚手架）、`tools\probe_api.ps1`（实网自检）。
3. 测试：`test/` 下单元 + widget 用例，覆盖协议算法与下载流水线关键节点。
4. `flutter build apk --release` 产物可安装运行。

### 2.2 验收清单（逐条勾）

- [ ] `flutter analyze` 0 issue（允许 `info` 级 lint，须在 PR 说明）。
- [ ] `flutter test` 全绿，用例数 ≥ 25，且 §10 的向量表全部落地。
- [ ] 冷启动进首页：轮播 + ≥4 个分节渲染出真实封面（非占位图）。
- [ ] 首页无限流可翻到第 3 页，下拉刷新回到第 1 页且滚动位置归零。
- [ ] 三 tab 切换：首页滚动位置、下载页输入内容、我的页开关状态均保留。
- [ ] 下载：批量输入 3 个车号 → 队列并发 3 → 产出 3 个 PDF 在 `Documents/JMComics/`，命名 `JM{id} - {title}.pdf`，重复下载生成 `(2)`。
- [ ] 下载中锁屏/切后台不中断（前台服务 + 通知进度），取消后临时文件清空。
- [ ] 深/浅主题各跑一遍，系统字体放大 1.3 无溢出。
- [ ] **配色符合 §7.1**：默认浅色白橙（底 `#FFFFFF`、主色 `#F26B0F`、正文 `#141413`），深色底 `#141413` 字 `#FAF9F5`，阅读器恒深色 `#0B0B0A`；页面里没有写死 hex（全部取自 `AppColors`）。
- [ ] **UI 无 emoji、无 `Icons.*`**：所有图标来自 `assets/icons/*.svg`（手绘 24×24 / stroke 1.75），`tools\check_ui_rules.ps1` 扫描 0 命中。
- [ ] 搜索：输入纯车号（`350234` / `JM350234` / 链接）→ 直接进详情页；输入关键词 → 发 GET 搜索请求并渲染结果页，可翻页。
- [ ] 阅读器双模式：上下滚动 / 左右翻页可切换；翻页模式下点左侧上一页、点右侧下一页、点中间出 HUD（进度条 + 退出），进度可拖动跳页并回写记忆。
- [ ] `tools\probe_api.ps1` 全绿（线路、promote、latest、categories、filter、chapter、scramble、封面、正文图）。

---

## 3. 技术选型与依赖

### 3.1 依赖清单（`pubspec.yaml`）

```yaml
name: jm_comic
description: JMComic 首页浏览 + 本地 PDF 下载客户端
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.5.0

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^2.6.1        # 状态管理（不用代码生成，手写 Provider）
  go_router: ^14.6.2              # 路由 + 三 tab 壳（StatefulShellRoute）
  dio: ^5.7.0                     # HTTP；底层 dart:io 天然 HTTP/1.1
  crypto: ^3.0.6                  # MD5
  pointycastle: ^3.9.1            # AES-256-ECB
  hive_ce: ^2.9.0                 # 下载记录 / feed 缓存
  hive_ce_flutter: ^2.2.0
  shared_preferences: ^2.3.3      # 线路表、主题模式
  path_provider: ^2.1.5
  cached_network_image: ^3.4.1    # 封面（带 UA/Referer 头）
  image: ^4.3.0                   # 解码 / 切片 / PNG 重编码
  pdf: ^3.11.1                    # 纯 Dart 写 PDF
  photo_view: ^0.15.0             # 阅读器缩放
  flutter_svg: ^2.0.17            # 自绘 SVG 图标（全项目禁用 emoji 与图标字体）
  flutter_foreground_task: ^8.17.0
  flutter_local_notifications: ^18.0.1
  media_store_plus: ^0.1.3        # 写公共 Documents/JMComics
  open_filex: ^4.6.0              # 打开导出的 PDF
  permission_handler: ^11.3.1     # POST_NOTIFICATIONS
  html: ^0.15.5                   # 首页 HTML 兜底抓取
  collection: ^1.18.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  mocktail: ^0.3.4
  http_mock_adapter: ^0.6.1

flutter:
  uses-material-design: true      # 保留框架兜底，但业务代码禁止 Icons.*（见 §7.0）
  assets:
    - assets/icons/               # 全部图标：自绘 SVG，24×24 / stroke 1.75
    - assets/illustrations/       # 空态、错误态插画
    - assets/images/              # 少量位图（无则留空目录 + .gitkeep）
```

> 版本号是**下限锚点**：`flutter pub get` 时按当前 stable 解析；出现解析冲突时取最新兼容版，并把结果写回本表。

### 3.2 选型理由（要改先看这里）

- **dio + dart:io**：`dart:io` 的 `HttpClient` 只走 HTTP/1.1，正好绕开 JM CDN 的 h2 preface 故障（`JmScript` 里 OkHttp 强制 `Protocol.HTTP_1_1` 的同一考量）。
- **Riverpod 手写 Provider**：让接手方可读性最高，不引入 build_runner 代码生成。
- **`pdf` 纯 Dart**：`JmScript` 用 Android `PdfDocument`；Dart 侧用 `pdf` + `image` 达成同样「一页一图、页尺寸=图尺寸、长边上限 14400」的语义。
- **`media_store_plus`**：`JmScript` 用 `MediaStore` 写 `Documents/JMComics/`；Flutter 侧首选同插件，失败降级 app 外部目录 + `open_filex`（见 §11）。

---

## 4. 目录结构与文件职责

> 已由 `tools\scaffold.ps1` 建好（27 个目录）。`android/`、`ios/` 由 `flutter create` 生成。

```
D:\data\product\JMComic\
├─ PLAN.md                     # 本文档
├─ README.md                   # 入口说明（3 行怎么跑起来）
├─ pubspec.yaml
├─ analysis_options.yaml
├─ android\  ios\              # flutter create 生成；android 需改 minSdk/权限/前台服务
├─ assets\icons\               # 自绘 SVG 图标（home/user/download/search/…，清单见 assets\README.md）
├─ assets\illustrations\       # 空态/错误态插画（SVG）
├─ assets\images\              # 位图（无则空目录）；加载占位不放图片，骨架是代码画的
├─ assets\README.md            # 素材规则 + 图标清单（新增图标必须同步这里）
├─ lib\
│  ├─ main.dart                # runApp + ProviderScope + Hive 初始化
│  ├─ app.dart                 # MaterialApp.router + 主题注入
│  ├─ core\
│  │  ├─ config\app_config.dart          # 版本号、并发上限、页大小、缓存 TTL
│  │  ├─ constants\jm_constants.dart     # 密钥、UA、默认域名、正则、排序枚举
│  │  ├─ theme\app_theme.dart            # M3 ColorScheme + 组件主题
│  │  ├─ theme\app_colors.dart           # seed / 渐变 / scrim
│  │  ├─ theme\app_typography.dart       # 字号字重表
│  │  ├─ icons\app_icons.dart            # SVG 图标常量表 + SvgIcon 组件（唯一的图标入口）
│  │  ├─ router\app_router.dart          # go_router + StatefulShellRoute（三 tab）
│  │  ├─ network\dio_factory.dart        # Dio 实例：超时、UA、cookie、重试拦截器
│  │  ├─ network\api_exception.dart      # JmApiException / JmContentException
│  │  ├─ image\image_scrambler.dart      # 切片段数算法（移植 ImageScrambler.kt）
│  │  ├─ image\image_processor.dart      # 切片还原 + PNG 重编码（移植 ImageProcessor.kt）
│  │  ├─ utils\jm_id_parser.dart         # 车号解析 / 批量分词（移植 JmIdParser.kt）
│  │  ├─ utils\file_names.dart           # PDF 命名清洗（移植 FileNames.kt）
│  │  ├─ utils\isolate_runner.dart       # compute() 包装（解码/还原在 isolate）
│  │  └─ utils\logger.dart               # 统一日志（release 关闭 debug）
│  ├─ data\
│  │  ├─ models\jm_album_summary.dart    # 列表项（首页/分类/搜索共用）
│  │  ├─ models\jm_album_detail.dart
│  │  ├─ models\jm_chapter.dart
│  │  ├─ models\jm_promote_module.dart
│  │  ├─ models\jm_category.dart
│  │  ├─ models\jm_search_page.dart
│  │  ├─ models\download_record.dart     # 对齐 DownloadRecord.kt
│  │  ├─ models\user_session.dart
│  │  ├─ sources\jm_crypto.dart          # token / AES 解密（移植 JmCrypto.kt）
│  │  ├─ sources\jm_endpoint_resolver.dart # 域名发现 + 线路挑选 + 持久化
│  │  ├─ sources\jm_api_client.dart      # 协议客户端（移植 JmApiClient.kt + 首页端点）
│  │  ├─ sources\jm_html_scraper.dart    # 首页 HTML 兜底解析
│  │  ├─ sources\jm_response_parser.dart # JSON → 模型（移植 JmResponseParser.kt + 扩展）
│  │  ├─ local\hive_init.dart
│  │  ├─ local\endpoint_store.dart       # 可用线路、img_host、appVersion
│  │  ├─ local\download_store.dart       # 下载记录 CRUD + 变更流
│  │  ├─ local\settings_store.dart       # 主题、并发、输出偏好
│  │  ├─ repositories\home_repository.dart   # 首页聚合 + 分页 + 缓存 + 降级
│  │  ├─ repositories\catalog_repository.dart# 分类/排序/列表分页
│  │  ├─ repositories\search_repository.dart # 车号判定 + /search 分页 + 搜索历史
│  │  ├─ repositories\album_repository.dart  # 详情 + 章节 + 阅读器图片
│  │  ├─ repositories\download_repository.dart # 投递任务、状态流
│  │  └─ repositories\session_repository.dart  # cookie/线路/版本状态
│  └─ features\
│     ├─ shell\shell_page.dart           # Scaffold + IndexedStack 式分支
│     ├─ shell\glass_nav_bar.dart        # 玻璃胶囊 Dock（三档）
│     ├─ home\home_page.dart
│     ├─ home\home_providers.dart
│     ├─ home\widgets\hero_banner.dart      # 轮播
│     ├─ home\widgets\category_chips.dart   # 粘性分类条
│     ├─ home\widgets\section_header.dart
│     ├─ home\widgets\album_card.dart       # 网格 / 横滑两种形态
│     ├─ home\widgets\cover_image.dart      # 拼封面 URL + 头 + 占位
│     ├─ home\widgets\feed_skeleton.dart    # shimmer 骨架
│     ├─ album\album_page.dart
│     ├─ album\album_providers.dart
│     ├─ album\widgets\chapter_tile.dart
│     ├─ search\search_page.dart          # 搜索页：车号直达详情 / 关键词走 GET 搜索
│     ├─ search\search_providers.dart
│     ├─ search\widgets\search_field.dart
│     ├─ search\widgets\result_grid.dart
│     ├─ reader\reader_page.dart
│     ├─ reader\reader_providers.dart
│     ├─ reader\reader_mode.dart           # enum ReaderMode { vertical, paged }
│     ├─ reader\widgets\reader_hud.dart    # 顶部退出 + 底部进度条（中间点击显隐）
│     ├─ reader\widgets\reader_tap_zones.dart # 左 / 中 / 右三分区点击
│     ├─ reader\widgets\page_turn_view.dart   # 左右翻页（电子书模式）
│     ├─ reader\widgets\scroll_reader_view.dart # 上下连续滚动模式
│     ├─ mine\mine_page.dart
│     ├─ mine\settings_page.dart
│     ├─ mine\about_page.dart
│     ├─ download\download_page.dart
│     ├─ download\download_providers.dart
│     ├─ download\widgets\download_input.dart
│     ├─ download\widgets\task_card.dart
│     └─ download\engine\
│        ├─ download_task.dart          # 任务实体 + 状态机
│        ├─ download_slots.dart         # 队列/并发信号量
│        ├─ download_coordinator.dart   # 入队、取消、重试（移植 DownloadCoordinator.kt）
│        ├─ download_worker.dart        # 单任务流水线（移植 JmDownloadWorker.kt）
│        ├─ pdf_exporter.dart           # 移植 PdfExporter.kt
│        ├─ pdf_sink.dart               # 移植 DocumentsPdfStore.kt
│        └─ notification_service.dart   # 前台服务 + 进度通知
├─ test\core\  test\data\  test\download\  test\features\
├─ test\fixtures\                      # 固化的 JSON / HTML 样例
├─ test\helpers\fixtures.dart
├─ tools\scaffold.ps1  tools\probe_api.ps1  tools\check_ui_rules.ps1
└─ docs\ui-draft.html                  # 六屏可点 UI 草稿（首页/搜索/详情/阅读器/下载/我的）
   docs\PROBE_RESULT_2026-11-14.txt    # 接口探测留档
```

---

## 5. JM 移动端协议层规格（实测）

### 5.1 基本约定

```dart
// lib/core/constants/jm_constants.dart
const kTokenSecret        = '185Hcomic3PAPP7R';   // 普通接口 token + data 解密
const kScrambleTokenSecret = '18comicAPPContent'; // /chapter_view_template 专用
const kDomainServerSecret  = 'diosfjckwpqpdfjkvnqQjsik';
const kFallbackAppVersion  = '2.1.13';
const kUserAgent = 'Mozilla/5.0 (Linux; Android 9; V1938CT Build/PQ3A.190705.11211812; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36';
const kDefaultApiHosts = <String>[
  'www.cdnbtd.cc', 'www.cdnutc.cc', 'www.cdnhjk.net',
  'www.cdngwc.cc', 'www.cdngwc.net', 'www.cdngwc.club',
];
const kDomainServerUrls = <String>[
  'https://rup4a04-c01.tos-ap-southeast-1.bytepluses.com/newsvr-2025.txt',
  'https://rup4a04-c02.tos-cn-hongkong.bytepluses.com/newsvr-2025.txt',
  'https://rup4a04-c03.tos-cn-beijing.bytepluses.com.cn/newsvr-2025.txt',
];
```

- 请求头：`token: md5hex(ts + secret)`，`tokenparam: "$ts,$appVersion"`，`User-Agent: kUserAgent`。
- `ts` = UTC 秒级时间戳字符串；`appVersion` 来自 `/setting.jm3_version`（拿不到用 `2.1.13`）。
- **必须先调 `/setting`**：它下发 5 个 cookie，后续请求必须携带（否则会被重定向）。
- 不要手动设 `Accept-Encoding`（交给 HttpClient 自动 gzip）。

### 5.2 域名发现与线路切换

> 2026-11-15 重写，实现见 `lib/data/sources/jm_endpoint_resolver.dart` / `jm_host_probe.dart` / `jm_host_catalog.dart`，说明见 `docs/NETWORK_MODULE.md`。

1. 发现源（并发，单源 6s 超时，任一可用即可）：
   - 内置种子 `assets/data/jm_hosts.json`（`tools\probe_hosts.ps1` 生成，含延迟/时间戳）；
   - 三个 TOS `newsvr-2025.txt` → 去头非 ASCII → `kDomainServerSecret` + `ts=""` 解密 → `Setting` / `Server` / **`jm3_Server`（带线路标签，含第 5 条线路）**；
   - 发布页 `jmcomictt.site` / `jmcomicgo.org` → 解析「國際通用 / 東南亞 / **內地 / 分流1 / 分流2**」→ 国内域名；
   - 开源镜像 `JMComic-Crawler-Python` 的 `DOMAIN_API_LIST` / `DOMAIN_IMAGE_LIST`。
2. 连通性判定必须跑完整链路：`GET /setting` + `token`/`tokenparam` → `code=200` → AES 解密 → 拿到 `jm3_version` / `img_host`。HTTP 200 但解不开 = 不可用（这正是旧实现的坑）。
3. 合并去重后按健康度排序：手填线路 → 新鲜 ok 按延迟升序 → 未知 → 失败且冷却中（10 分钟）；健康记录 30 分钟 TTL，写入 `endpoint_store` 的 `jm_host_health`。
4. 冷启动只要有一条新鲜 ok 线路就不阻塞探测；否则首批 4 台并发实测（5s/台），有 ok 即停。设置页「线路测速」可全量重测。
5. 图床顺序：`/setting.img_host` → 种子实测 ok → **国内 `comic18j-*` 兜底** → 内置默认。

### 5.3 响应解密

外层固定 `{"code":200,"data":"<base64>"}`，`code != 200` 时读 `errorMsg` / `msg` 抛可读异常。
`data` 解密：**AES-256-ECB / PKCS7**，key = `ASCII(md5hex(ts + kTokenSecret))` 的 **全部 32 个字节**（不是前 16 字节，也不是 md5 的 16 个原始字节），Base64 先去掉所有空白（MIME 容错），再按 4 取模补 `=`。

> ⚠️ 2026-11-15 实网复核：旧实现按 `sublist(0, 16)` 走 AES-128，真实响应 PKCS7 去填充必失败 → 每条线路都「HTTP 200 但解密失败」，看起来就是「连通性检测有问题、全线路不可用」。现场证据：同一 ts 下 16 字节 key 抛 `Padding is invalid`，32 字节 key 解出 `{"version":"1.8.2",…}`；`test/fixtures/setting_envelope_live.json` + `test/data/jm_crypto_test.dart` 已固化该向量。
>
> ⚠️ 与原项目差异：`/promote`、`/latest` 解密后是**顶层 JSON 数组**（`[{...}]`），不是对象。`JmScript` 只处理对象，Dart 侧 `apiDecoded()` 必须返回 `dynamic`（`Map`/`List` 都可能），再由上层 parser 定型。

### 5.4 端点表（全部实测通过）

| # | 端点 | 关键参数 | 返回结构 | 用途 |
|---|---|---|---|---|
| 1 | `/setting` | — | `{jm3_version, img_host, bundle_url, ipcountry, ...}` + cookie | 引导 |
| 2 | `/promote` | — | `[{id,title,slug,type,filter_val,content:[album…]}]` 共 8 个模块 | 首页轮播 + 分节 |
| 3 | `/latest` | `page`（1 起） | `[album…]` 每页 80 | 最新上架 |
| 4 | `/categories` | `page=1` | `{categories:[{id,name,slug,total_albums,type,sub_categories:[{CID,name,slug}]}]}` | 分类 chips |
| 5 | `/categories/filter` | `page,order=,c=<分类id>,o=<排序>` | `{search_query,total,content:[album…]}`，`total` 上限 10000 | 无限流 |
| 6 | `/search` | `main_tag=0,search_query,page,o,t=a` | `{search_query,search_type,total,content[]}`；命中车号时 `{redirect_aid:"350234",total:1,content:[]}` | 搜索 |
| 7 | `/album` | `id` | 详见 §5.5 | 详情 |
| 8 | `/chapter` | `id`（章节/单本 id） | `{id,name,images:["00001.webp",…],tags,series_id,…}` | 页面清单 |
| 9 | `/chapter_view_template` | `id,mode=vertical,page=0,app_img_shunt=1,express=off,v=ts`（**用 scramble 密钥**） | HTML，正则 `var\s+scramble_id\s*=\s*(\d+)\s*;` | 切片阈值 |
| 10 | `/favorite`（GET） | `page`（1 起）、`o=mr\|mp`、`folder_id`（默认 0） | `{count,total,list:[{id,author,name,image,category,category_sub,…}]}` | 收藏列表（需登录） |
| 11 | `/favorite`（POST，multipart） | `aid` | `{msg,status:"ok",type:"add"\|"remove"}` | **切换**收藏（需登录） |
| 12 | `/login`（POST，multipart） | `username`、`password` | `{uid,username,album_favorites,album_favorites_max,…}` + cookie（含 `AVS`） | 登录，取收藏上限 |
| 13 | `/watch_list` | `page` | 与 #10 同构 | 观看历史（需登录） |
| 14 | `/like`（POST，multipart） | `id`（专辑 id） | `{code,msg,status:"success"}`（**明文 JSON**，不带计数、无取消接口） | 点赞（客户端要求登录后调用） |
| 15 | `/forum` | `page`、`aid`、`mode=manhua` | `{list:[{CID,UID,username,nickname,likes,addtime,parent_CID,content,photo,spoiler,replys[]}],total:"12"}` | 评论列表（游客可读） |
| 16 | `/comment`（POST，multipart） | `comment`、`aid`、`status`（`1`=剧透）、`comment_id`（回复父 id） | `{msg,status:"ok",aid,cid,spoiler}` | 发评论（需登录，未登录返回 401） |

> #10–#16 的字段与参数取自 `Dedicatus546/jm-mobile` 的 Retrofit 定义与 `hect0x7/JMComic-Crawler-Python` 的 `favorite_folder`，并由 `tools/probe_forum.ps1` 实测复核；收藏/会话见 `docs/FAVORITES.md`，互动见 `docs/INTERACTION.md`。

`/categories` 实测 10 个顶层分类（`total_albums` 为服务端计数）：

| id | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| name | 最新A漫 | 同人 | 單本 | 短篇 | 其他類 | 韓漫 | English Manga | Cosplay | 3D | 禁漫漢化組 |

`id=1`（同人）的子分类样例：`漢化 / 日語 / CG圖集 / 禁漫去碼 / 禁漫上色`（字段名 `CID`、`name`、`slug`）。

`/promote` 实测 8 个模块：
| id | type | filter_val | 条目数 | title |
|---|---|---|---|---|
| 26 | `promote` | 26 | 30 | 連載更新→右滑看更多→ |
| 29 | `promote` | 29 | 30 | C108&推薦本本 |
| 30 | `promote` | 30 | 30 | 禁漫去碼&全彩化 |
| 998 | `not_in_category_id` | — | 30 | 禁漫漢化組 |
| 999 | `category_id` | 5 | 30 | 韓漫更新 |
| 1000 | `category_id` | 4 | 30 | 其他更新 |
| 1001 | `library` | — | 3 | 禁漫書庫 |
| 1002 | `novels` | — | 6 | 禁漫小說 |

`/categories/filter` 的 `o`（实测均返回 200，`total` 有差异）：

| o | 首条 id | 语义（UI 文案） |
|---|---|---|
| `mr` | 1490702 | 最新更新 |
| `mv` | 1114751 | 最多观看（total 10000） |
| `mv_m` | 1114751 | 月榜（total 2072） |
| `mv_w` | 1114751 | 周榜（total 795） |
| `mv_t` | 1114751 | 日榜（total 121） |
| `md` | 566986 | 最新上架 |
| `mp` | 235953 | 人气推荐 |

> `o` 的文案是 UI 展示用近似值：前 5 个已由 `total` 差异证实为「总/月/周/日」榜，`md`、`mp` 只证实了可返回数据，落地时按实际首位内容再校一次文案。

### 5.5 字段表

**列表项（promote/latest/filter/search 通用）**

```json
{"id":"1485385","author":"N/A","name":"轉生到不認識的世界…","image":"",
 "category":{"id":"2","title":"單本"},"category_sub":{"id":null,"title":null},
 "liked":false,"is_favorite":false,"update_at":1794643443,"adddate":"2026-11-14"}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | string | 车号（数字字符串） |
| `name` / `author` | string | 标题 / 作者，`author` 可能是 `N/A` |
| `image` | string | **恒为空串** → 封面按 §5.6 自行拼 |
| `category.id` / `.title` | string | 一级分类（`1` 同人 / `2` 單本 / `4` 其他類 / `5` 韓漫…） |
| `category_sub` | object \| null | 子分类，可能 `id/title` 均 null |
| `liked` / `is_favorite` | bool | 赞 / 收藏态（未登录时为 false） |
| `update_at` | int | 秒级时间戳 |
| `adddate` | string | `yyyy-MM-dd` |

**专辑详情 `/album`** 实测字段：`id, name, images, addtime, description, total_views, total_photos, likes, series, series_id, real_link, comment_total, author, tags, works, actors, related_list, liked, is_favorite, is_aids, price, purchased`。
- `series`: `[{id,sort,name}]`；**单本漫画该数组为空**，此时章节 = 专辑自身 `id`。
- `series_id` 非 `"0"` 且 ≠ `id` 时，说明传的是章节号，需要按 `series_id` 再看一次（同 `JmScript` 的重定向逻辑）。
- `total_photos`: **字符串**，需 `int.tryParse`。

**章节 `/chapter`**：`id, series, tags, name, images, addtime, real_link, series_id, is_favorite, liked`；`images` 是**文件名数组**（如 `["00001.webp", …]`，实测 19 张），顺序即阅读顺序。

### 5.6 封面与正文图 URL

```
封面:   https://{img_host}/media/albums/{albumId}_3x4.jpg     # 实测 200 image/jpeg 87 KB
备选:   https://{img_host}/media/albums/{albumId}.jpg         # 实测 200 image/jpeg 66 KB
        https://{img_host}/media/albums/{albumId}_3x4.webp    # 实测 502，别用
正文图: https://{img_host}/media/photos/{photoId}/{filename}   # 实测 200 image/webp 569 KB
```

`img_host` 来自 `/setting.img_host`（实测值形如 `https://cdn-msp12.jmdanjonproxy.xyz` / `https://tencent.jmdanjonproxy.xyz`，会漂移，必须动态读取）。

图片请求头（缺一可能 403 或返回 HTML）：

```dart
{
  'User-Agent': kUserAgent,
  'Referer': 'https://$apiHost/',
  'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  'X-Requested-With': 'com.JMComic3.app',
}
```

### 5.7 切片还原算法（必须逐字对齐）

**段数**（`image/ImageScrambler.kt`）：

```
photoId < scrambleId            → 0    （不切）
photoId < 268850                → 10
否则 modulus = photoId < 421926 ? 10 : 8
     段数 = (md5hex("$photoId${filename去扩展名}").lastCodeUnit % modulus) * 2 + 2
```

`filename` 先 `substringBefore('?')` → `substringAfterLast('/')` → `substringBeforeLast('.')`。

**还原**：把源图纵向切成 `segments` 段，再**倒序**贴回，第一段吃掉余数：

```
remainder = h % segments; base = h ~/ segments
for i in 0..<segments:
    sliceH = base
    srcTop = h - base*(i+1) - remainder
    dstTop = base*i
    if i == 0: sliceH += remainder
    else:      dstTop += remainder
    copy(row srcTop..srcTop+sliceH) → (row dstTop..)
```

### 5.8 可直接用的 Dart 片段

```dart
// lib/data/sources/jm_crypto.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

String md5Hex(String input) => crypto.md5.convert(utf8.encode(input)).toString();

String buildToken(String ts, {String secret = '185Hcomic3PAPP7R'}) => md5Hex(ts + secret);

/// Base64(MIME 容错) → AES-256-ECB/PKCS7 → UTF-8
String decryptPayload(String encoded, String ts, {String secret = '185Hcomic3PAPP7R'}) {
  final key = ascii.encode(md5Hex(ts + secret)); // 32 个 ASCII 字符 = 32 字节 = AES-256 key
  final keyBytes = Uint8List.fromList(key);
  var clean = encoded.replaceAll(RegExp(r'\s'), '');
  while (clean.length % 4 != 0) { clean += '='; }
  final cipherText = base64.decode(clean);
  final cipher = PaddedBlockCipherImpl(PKCS7Padding(), ECBBlockCipher(AESEngine()));
  cipher.init(false, PaddedBlockCipherParameters<CipherParameters?, CipherParameters?>(
      KeyParameter(keyBytes), null));
  return utf8.decode(cipher.process(cipherText));
}
```

> 说明：`md5hex` 是 32 个十六进制字符；AES-256 需要 32 字节 key，直接把 `md5hex(...)` 的 ASCII 字节全量喂给 `AESEngine`。**不要**截断成 16 字节（旧版就是这么写的，实网必失败），也**不要**用 `md5.convert(ts+secret).bytes`（那是 16 个原始字节，值不同）。
> `PaddedBlockCipherParameters` 的泛型在部分 pointycastle 版本上收得紧，编译报错时改成 `PaddedBlockCipherParameters<KeyParameter, Null>(KeyParameter(keyBytes), null)` 或 `as CipherParameters` 强转。

```dart
// lib/core/image/image_scrambler.dart
int segmentCount({required int scrambleId, required int photoId, required String filename}) {
  if (photoId < scrambleId) return 0;
  if (photoId < 268850) return 10;
  final modulus = photoId < 421926 ? 10 : 8;
  final noExt = filename.split('?').first.split('/').last.split('.').first;
  final hash = md5Hex('$photoId$noExt');
  return (hash.codeUnitAt(hash.length - 1) % modulus) * 2 + 2;
}
```

```dart
// lib/core/utils/jm_id_parser.dart —— 与 JmIdParser.kt 同语义
final _pathId  = RegExp(r'/(?:album|photo)/(\d+)', caseSensitive: false);
final _queryId = RegExp(r'[?&](?:id|album_id|photo_id|aid)=(\d+)', caseSensitive: false);
final _plainId = RegExp(r'^(?:JM)?\s*(\d+)$', caseSensitive: false);
final _digits  = RegExp(r'\d+');
final _seps    = RegExp(r'[\s,，、;；]+');

String? parseJmId(String input) {
  final v = input.trim();
  if (v.isEmpty) return null;
  final candidate = _pathId.firstMatch(v)?.group(1)
      ?? _queryId.firstMatch(v)?.group(1)
      ?? _plainId.firstMatch(v)?.group(1)
      ?? _digits.firstMatch(v)?.group(0);
  if (candidate == null) return null;
  final normalized = candidate.replaceFirst(RegExp(r'^0+'), '');
  final result = normalized.isEmpty ? '0' : normalized;
  return (result == '0' || result.length > 10) ? null : result;
}
```

```dart
// lib/core/utils/file_names.dart —— 与 FileNames.kt 同语义
String pdfName(String albumId, String title) {
  final reserved = RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'); // 对应 Kotlin 的 [<>:"/\|?*\p{Cntrl}]
  var clean = title.replaceAll(reserved, '_').replaceAll(RegExp(r'\s+'), ' ').trim();
  clean = clean.replaceAll(RegExp(r'^[. ]+|[. ]+$'), '');
  clean = _takeCodePoints(clean, 80);
  if (clean.isEmpty) clean = 'comic';
  return 'JM$albumId - $clean.pdf';
}

/// 按 Unicode 码点截断，emoji 不会被劈成半个代理对（Kotlin 用 offsetByCodePoints）
String _takeCodePoints(String input, int maxCount) {
  final runes = input.runes.toList();
  if (runes.length <= maxCount) return input;
  return String.fromCharCodes(runes.take(maxCount)).trimRight();
}
```

---

## 6. 首页实现规格

### 6.1 数据流

```
JmEndpointResolver.discover()            // 3 源域名发现 → 持久化
  └─ JmApiClient.prepare()               // /setting → cookie + imgHost + appVersion
       ├─ fetchPromote()                 // 8 模块（首页骨架）
       ├─ fetchLatest(page:1)            // 80 条（最新）
       ├─ fetchCategories()              // 分类 chips
       └─ fetchFilter(page:1, c:0, o:mr) // 80 条（瀑布流第一页）
                 ↓
        HomeRepository.fetchFeed()        // 聚合 HomeFeed + 写 Hive 缓存
                 ↓
        homeFeedProvider (AsyncNotifier)  // UI 订阅；refresh / loadMore
```

`HomeFeed` 结构：

```dart
class HomeFeed {
  final List<PromoteBanner> banners;         // promote 前 6 个模块各取首项
  final List<JmPromoteModule> modules;       // 全部 8 个模块（横滑分节）
  final List<JmAlbumSummary> latest;         // 前 40 条
  final List<JmAlbumSummary> grid;           // 第一页 80 条
  final int gridPage;                        // 已加载到第几页
  final int gridTotal;                       // 服务端 total（上限 10000）
  final DateTime updatedAt;
  final bool fromCache;
}
```

### 6.2 分页与缓存规则

- 触发加载：`scrollController.offset > maxScrollExtent - 500`。
- 下一页失败：保留已有内容 + 底部「重试」条，不弹全屏错误。
- `grid` 用「按 id 去重 + 保序」合并（`/latest` 与 `filter` 会有重叠）。
- 缓存：`HomeFeed` 以 JSON 存 Hive（TTL 30 分钟）；冷启动先渲染缓存（顶部标一条「缓存内容 · 12:31 更新」），再后台刷新。
- **标签页内存缓存（0.3.0 起强制）**：`homeFeedProvider` 只 `build()` 一次，用 `ref.listen` 监听分类/排序；切到已缓存的组合立刻 `AsyncData(cached)`（不闪骨架屏、不清滚动位置），只有超过 `AppConfig.categoryCacheTtl`（5 分钟）才后台静默刷一页；刷新失败保留旧内容并给一行「刷新失败，先看上次内容」。
- **空闲预热**：首屏出来后按 700ms 间隔给前 3 个分类各发 **1 次** `/categories/filter`（不重复取 promote/latest/categories），预热条目复用当前轮播/分节、只替换网格；provider 销毁时取消计时器。
- 空/错态：整页错误态（插画 + 重试），分区级失败只隐藏该分区。

### 6.3 HTML 兜底（`JmHtmlScraper`）

仅在 API 全线路失败时启用，用 `html` 包解析：

| 目标 | 选择器（集中在 `jm_html_scraper.dart` 常量区） |
|---|---|
| 轮播 | `#index-carousel a[href*="/album/"]` |
| 分节 | `div.list-group` → `p.list-group-title` + `div.list-group-item a[href*="/album/"]` |
| 封面 | 卡片内 `img` 的 `data-original` / `src` |
| 标题 | 卡片 `div.video-title` 文本 |

配套 `test/fixtures/home.html`（M2 抓一份真实 HTML 存进去）；选择器改动必须同步更新该 fixture 的断言。

---

## 7. UI 规格（现代 Material 3）

> **先看交互草稿**：`docs\ui-draft.html`（浏览器直接打开，无需服务器）。六屏可点原型（首页 / 搜索 / 详情 / 阅读器 / 下载 / 我的）+ 25 个按钮编号，右侧逐条列出「控件 → 操作逻辑 → 接口/参数」和真实加载时序；点编号跳到对应说明行，点 Dock / 卡片 / 按钮就是真实跳转。静态截图：`docs\ui-draft*.png`。
> 实现时以本节的尺寸/配色为视觉标准，以草稿里的编号为功能清单（一个编号 = 一个可点元素 = 一条用例）。

### 7.0 素材与图标规范（硬规则）

**素材放哪儿**

| 目录 | 放什么 | 约定 |
|---|---|---|
| `assets/icons/` | **所有 UI 图标**，一个图标一个 `.svg` | Dock、AppBar、任务卡、阅读器 HUD 全部从这里取；现有 28 个（0.3.0 新增 `star` / `star-filled` / `heart` / `heart-filled` / `comment` / `send`） |
| `assets/illustrations/` | 空态 / 错误态 / 引导插画 `.svg` | 160×120 起，现 3 张（`empty-search` / `empty-download` / `error-network`） |
| `assets/images/` | 位图（品牌标记、加载动画、角标、二维码） | 由 `tools/build_app_assets.py` 从 `img/` 派生；**加载占位不放这里** |
| `assets/fonts/` | 自托管正文字体（可选） | **不放图标字体** |

**三条硬规则**

1. **不用 emoji**：`🔍 ⬇ ⌂ 🙂 ☆ ☺ ⤓ ⌄` 之类字符不许出现在按钮、状态胶囊、提示文案里；对应的图标全部用 `assets/icons/*.svg`。
2. **不用图标字体**：业务代码里不出现 `Icons.*`，不接 `font_awesome_flutter`；统一走 `lib/core/icons/app_icons.dart` 的 `SvgIcon` 组件（`SvgPicture.asset` + `colorFilter: ColorFilter.mode(color, BlendMode.srcIn)`），颜色靠 `currentColor` 继承主题。
3. **SVG 规格**：`viewBox="0 0 24 24"`、`fill="none"`、`stroke="currentColor"`、`stroke-width="1.75"`、`stroke-linecap/linejoin="round"`；展示尺寸按 16 / 20 / 24 取用，SVG 内不写死颜色。

**加载态怎么做（同样不引图片素材）**

| 场景 | 做法 |
|---|---|
| 首页首屏 | `FeedSkeleton`：轮播 1 + 横滑 1 + 网格 6 的灰块，`ShaderMask` + `AnimationController` 做 shimmer（1.2s 循环） |
| 封面加载中 | 纯色块 + 轻 shimmer；失败用 `error-network.svg` 的缩略版 |
| 下载 / 翻页中 | `CircularProgressIndicator(strokeWidth: 2.4)`，不引素材包 |
| 空态 | `assets/illustrations/*.svg` + 一句文案 + 一个主按钮 |

**CI 守卫**：`tools\check_ui_rules.ps1` 扫 `lib/` 与 `assets/`，命中 emoji 区字符（`U+2190-21FF`、`U+2300-27BF`、`U+1F300-1FAFF`、`U+FE0F`）、`Icons.` 调用、非 `.svg` 图标引用即失败并给出行号；M6 收尾必跑。


### 7.1 主题与配色（已定稿，按此实现，不许自行改色）

**默认外观 = 浅色「白橙」**；深色为第二外观。两套都是固定 token，**不从 seed 反推**（`ColorScheme.fromSeed` 会把橙色洗淡，也会让深色背景偏离 `#141413`），直接 `ColorScheme(...)` 显式赋值。

**浅色（默认）：白底 + 橙主色**

| token | 值 | 用途 |
|---|---|---|
| `background` / `surface` | `#FFFFFF` | 页面底色、卡片底色 |
| `surfaceContainer` | `#FBF8F3` | 卡片/输入框第二层（暖白） |
| `surfaceContainerHigh` | `#F5F0E8` | 骨架块、chip 未选中底 |
| `outline` / `outlineVariant` | `#EBE3D8` / `#F2ECE2` | 1px 描边、分割线 |
| `primary`（橙） | `#F26B0F` | 主按钮、选中态、链接、进度条 |
| `onPrimary` | `#FFFFFF` | 橙底上的文字/图标 |
| `primaryContainer` | `#FFE8D5` | 选中胶囊底、收藏高亮底 |
| `onPrimaryContainer` | `#7A3200` | 橙容器上的文字 |
| `secondary`（暖黄橙） | `#E89B2C` | 次强调、评分、榜单角标 |
| `onSurface` / `onBackground`（正文） | `#141413` | 标题与正文 |
| `onSurfaceVariant`（次要文字） | `#6B6862` | 作者、计数、说明 |
| `error` | `#C6413A` | 失败、删除 |

**深色：`#141413` 底 + `#FAF9F5` 字**

| token | 值 | 用途 |
|---|---|---|
| `background` | `#141413` | **页面底色（硬要求）** |
| `surface` | `#1B1B19` | 卡片底（比背景亮一档） |
| `surfaceContainer` | `#232320` | 输入框、任务卡内层 |
| `surfaceContainerHigh` | `#2C2C28` | 骨架块、未选中 chip |
| `outline` / `outlineVariant` | `#3A3A35` / `#2A2A26` | 描边、分割线 |
| `onSurface` / `onBackground`（正文） | `#FAF9F5` | **前景字（硬要求）** |
| `onSurfaceVariant`（次要文字） | `#A9A69D` | 作者、计数、说明 |
| `primary`（橙，深色下提亮） | `#FF8A3D` | 主按钮、选中态、进度条 |
| `onPrimary` | `#1A0F05` | 橙底上的文字 |
| `primaryContainer` | `#3B2412` | 选中胶囊底 |
| `onPrimaryContainer` | `#FFD9BE` | 橙容器上的文字 |
| `secondary` | `#FFB25C` | 次强调 |
| `error` | `#FF6B5E` | 失败、删除 |

**规则**

1. 浅色是默认：首次启动 `ThemeMode.light`（不是 `system`）；设置里可切「浅色 / 深色 / 跟随系统」。
2. 橙色只做强调，**不做大面积底色**：一屏内橙色面积 ≤ 15%，主按钮一屏最多一个。
3. 圆角：卡片 16、封面 16/20、胶囊 999、面板 24。
4. 浅色阴影用 `rgba(20,20,19,.06)`；深色不用阴影，用 `outline` 1px 描边 + `surface` 提亮层次。
5. **阅读器永远是深色**（`#0B0B0A` 底 + `#FAF9F5` 字），不跟随主题，避免白底刺眼；HUD 用 `rgba(11,11,10,.9)`。
6. 动效：`PageTransitionsTheme` 用 `FadeForwardsPageTransitionsBuilder`；Hero 过渡封面；Dock 选中态 `elasticOut` 200ms。
7. 代码落点：`lib/core/theme/app_colors.dart` 只放上面两张表（常量 + `lightScheme` / `darkScheme`），`app_theme.dart` 只做组件主题映射，**禁止在 widget 里写死 hex**。

```dart
// lib/core/theme/app_colors.dart（照抄即可）
abstract final class AppColors {
  // 浅色（白橙）
  static const lightBg = Color(0xFFFFFFFF);
  static const lightSurfaceContainer = Color(0xFFFBF8F3);
  static const lightSurfaceContainerHigh = Color(0xFFF5F0E8);
  static const lightOutline = Color(0xFFEBE3D8);
  static const lightPrimary = Color(0xFFF26B0F);
  static const lightPrimaryContainer = Color(0xFFFFE8D5);
  static const lightOnPrimaryContainer = Color(0xFF7A3200);
  static const lightInk = Color(0xFF141413);
  static const lightInkVariant = Color(0xFF6B6862);
  static const lightError = Color(0xFFC6413A);

  // 深色（#141413 底 + #FAF9F5 字）
  static const darkBg = Color(0xFF141413);
  static const darkSurface = Color(0xFF1B1B19);
  static const darkSurfaceContainer = Color(0xFF232320);
  static const darkSurfaceContainerHigh = Color(0xFF2C2C28);
  static const darkOutline = Color(0xFF3A3A35);
  static const darkPrimary = Color(0xFFFF8A3D);
  static const darkPrimaryContainer = Color(0xFF3B2412);
  static const darkOnPrimaryContainer = Color(0xFFFFD9BE);
  static const darkInk = Color(0xFFFAF9F5);
  static const darkInkVariant = Color(0xFFA9A69D);
  static const darkError = Color(0xFFFF6B5E);

  // 阅读器（恒定深色，不随主题）
  static const readerBg = Color(0xFF0B0B0A);
  static const readerInk = Color(0xFFFAF9F5);

  static const lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary, onPrimary: Colors.white,
    primaryContainer: lightPrimaryContainer, onPrimaryContainer: lightOnPrimaryContainer,
    secondary: Color(0xFFE89B2C), onSecondary: Colors.white,
    surface: lightBg, onSurface: lightInk,
    surfaceContainerHighest: lightSurfaceContainerHigh,
    onSurfaceVariant: lightInkVariant,
    outline: lightOutline, error: lightError, onError: Colors.white,
  );

  static const darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary, onPrimary: Color(0xFF1A0F05),
    primaryContainer: darkPrimaryContainer, onPrimaryContainer: darkOnPrimaryContainer,
    secondary: Color(0xFFFFB25C), onSecondary: Color(0xFF1A0F05),
    surface: darkBg, onSurface: darkInk,
    surfaceContainerHighest: darkSurfaceContainerHigh,
    onSurfaceVariant: darkInkVariant,
    outline: darkOutline, error: darkError, onError: Color(0xFF1A0F05),
  );
}
```

### 7.2 壳体与 Dock（三档：首页 / 我的 / 下载）

- `StatefulShellRoute.indexedStack` 三个 `StatefulShellBranch` → 天然保留各 tab 的 Navigator 栈。
- Dock 自定义（不用系统 `NavigationBar`）：
  - 外层 `SafeArea` + 水平 16 内缩，高 64，`ClipRRect(24)`。
  - `BackdropFilter(blur: 24)` + `Container(color: surface.withOpacity(.72))` + 1px 描边。
  - 选中项：胶囊底色 `primary.withOpacity(.14)` + 图标填充 + 文字 12px w600；未选中：`onSurfaceVariant`，无文字底（或 11px）。
  - 点击 `HapticFeedback.selectionClick()`；切换用 `AnimatedContainer` 180ms。
- 顺序按用户要求：**首页 → 我的 → 下载**。

### 7.3 首页

| 区块 | 规格 |
|---|---|
| AppBar | `SliverAppBar(floating: true, pinned: false)`；滚动 > 40px 时背景 `surface.withOpacity(.82)` + blur；左侧「JMComic」字标（宽 96，`FontWeight.w800`，字距 -0.5），右侧搜索、主题切换 |
| 搜索 | 点击进搜索页（§7.4）。**输入是车号 → 直接进详情页**（不经过结果页）；输入是关键词 → GET 搜索接口出结果页 |
| 轮播 | 高 180，左右 margin 16，圆角 20，`PageView` 自动 5s，`Timer` 在 `dispose` 停止；底部渐变 scrim 高 88，标题 2 行 ellipsis + 分类徽标；指示点 6×6（激活 18×6 胶囊） |
| 分类条 | 高 44，`SliverPersistentHeader(pinned: true)`；chip 高 32、圆角 999、选中 `primary` 实底；数据来自 `/categories`（实测 10 个顶层：`0 最新A漫 / 1 同人 / 2 單本 / 3 短篇 / 4 其他類 / 5 韓漫 / 6 English Manga / 7 Cosplay / 8 3D / 9 禁漫漢化組`）→ 点击切 `c=<id>` 并重置分页 |
| 分节头 | 标题 16 w700 + 「更多 ›」12 `onSurfaceVariant` |
| 横滑分节 | 每模块 `SizedBox(height: 232)` + `ListView.horizontal`，卡片宽 148，封面 3:4，标题 2 行 |
| 瀑布流 | 双列 `SliverGrid`，`childAspectRatio: 0.58`（封面 3:4 + 2 行标题），`crossAxisSpacing 12`、`mainAxisSpacing 16` |
| 骨架 | 首屏未就绪时渲染 shimmer（轮播 1 + 横滑 1 + 网格 6） |
| 刷新 | `RefreshIndicator`（`edgeOffset: 56`，避免与 AppBar 冲突） |

### 7.4 搜索页（车号直达 / 关键词走 GET）

入口：首页 AppBar 搜索框、我的页「搜索历史」。

**输入判定 `resolveQuery(String input)`（纯本地，先判再发请求）**

| 输入形态 | 判定结果 | 动作 |
|---|---|---|
| `350234` / `JM350234` / `/album/350234/` / `?id=350234` / `车号：350234` | `JmIdParser.parse` 非空 | **不进结果页**：直接 `push /album?id=<id>` 进详情，返回即回搜索页 |
| 其它非空文本 | 关键词 | GET `/search?main_tag=0&search_query=<urlencode(q)>&page=1&o=mr&t=a` → 渲染结果页 |
| 空 | — | 显示搜索历史 + 热门词，不发请求 |

双保险：关键词形态若命中了车号，JM 服务端会返回 `redirect_aid`，拿到它照样跳详情。

**页面结构**

| 区块 | 规格 |
|---|---|
| 搜索框 | 高 44、圆角 999、前缀 `search.svg`、右侧「取消」；`autofocus`，`textInputAction: search`，回车触发 |
| 实时提示 | 输入时下方一行小字：`识别为车号 JM350234 · 回车直达详情` / `关键词 · 回车搜索`（本地判定，不请求） |
| 历史 | 最多 10 条 chip，点击回填并立即搜索；右「清空」；存 Hive |
| 结果头 | `共 N 条 · “关键词”`，右侧 `grid.svg` / `list.svg` 切视图 |
| 结果网格 | 复用 `AlbumCard`，双列；翻页同首页（`/search` 每页 80，触底加载） |
| 空结果 | `empty-search.svg` + 「没有找到相关本子」+ 「换个关键词」按钮 |

### 7.5 详情页

- 结构：`CustomScrollView`；`SliverAppBar(expandedHeight: 260, pinned: true)`，背景 = 封面 + `blur(28)` + 遮罩，前景小封面 96×128 圆角 12。
- 信息区：标题 20 w700（最多 3 行）、作者、`tags` 流式 chips；统计条四列（页数 / 浏览 / **喜欢** / 评论）。`/album.likes` 是站点的「喜歡」数，不要标成「收藏」。
- **动作条（统计条下方，0.3.0）**：`heart.svg`「点赞 N」+ `comment.svg`「评论 N / 写评论」；点赞未登录先弹「登录后才能操作」→ 去登录；服务端 `/like` 不回计数，客户端乐观 +1 且不提供取消。
- **评论区（章节之后、相关推荐之前）**：`CommentSection`，先铺 5 条 + 「查看全部 N 条评论」展开 + 「加载更多评论」分页（每页 20）；每条含头像（无头像用昵称首字）、昵称、相对时间、正文、`剧透` 标签、点赞数、`回复`；底部输入条「说点什么…」打开写评论面板（500 字上限 + 含剧透开关），发送成功回第 1 页并 toast 服务端文案。
- 章节列表：`series` 非空按 `sort` 升序去重，每行「第 N 话 · 标题（XP）」+ `forward.svg`；`series` 为空时只有一行「全一话（XP）」。
- **底部 CTA（两按钮）**：
  - 主按钮 **「开始阅读」**（`play.svg`，flex 撑满）→ 进阅读器；有记忆时文案变「继续阅读 · 第 12 页」，点击直达该页。
  - 次按钮「下载」（`download.svg`，108 宽）→ 投下载队列并切到下载 tab。
- 右上角：**`star.svg` / `star-filled.svg`（五角星，描边=未收藏、实心=已收藏）**、`share.svg`（复制链接）。
- 相关推荐：`related_list` 底部双列 6 个。

### 7.6 阅读器（双模式，核心交互）

进入方式：详情页「开始阅读」；下载完成的任务卡「打开」；也可从「继续阅读」带页码进入。

**两种模式（`ReaderMode`，HUD 内切换，选择记 Hive，下次默认沿用）**

| 模式 | 图标 | 交互形态 |
|---|---|---|
| 左右翻页（电子书，默认） | `page-mode.svg` | 横向 `PageView`，整屏一页，页面滑入滑出；**点击分区翻页**（见下） |
| 上下滚动（条漫） | `scroll-mode.svg` | 纵向连续拼页 `CustomScrollView`，中间点击呼出 HUD |

**左右翻页模式的点击分区（必须按此实现）**

```
┌──────────────┬────────────────┬──────────────┐
│   左 30%     │     中 40%     │    右 30%    │
│  上一页      │  HUD 显隐      │   下一页     │
└──────────────┴────────────────┴──────────────┘
```

- 左区 → `prevPage()`；已在第 1 页时 `HapticFeedback.lightImpact()` + 水平回弹 8px / 200ms，不弹提示框。
- 右区 → `nextPage()`；最后一页同样回弹 + 轻震。
- 中区 → 切换 HUD；HUD 显示后 3s 无操作自动隐藏（翻页、拖进度条都重置计时）。
- 分区用 `GestureDetector(behavior: HitTestBehavior.opaque)` 叠在图片层上；**双指缩放时禁用分区点击**（`InteractiveViewer.onInteractionStart` 置 `zoomed=true`，缩回 1.0 才恢复），否则拖动会误翻页。
- **双指缩放（0.3.0 起两种模式都支持）**：每页包一层 `InteractiveViewer(minScale: 1, maxScale: 4)`，缩放中把 `PageView` / 纵向 `ListView` 的 `physics` 切成 `NeverScrollableScrollPhysics`，把拖动让给图片平移；双击任意位置 1.0 ↔ 2.2（以双击点为中心）；缩回 1.0 附近自动 `Matrix4.identity()` 归位。
- **翻页动画开关必须生效**：设置里的 `pageTurnAnimation` 为 false 时 `_goToPage` 走 `jumpToPage`（瞬切），为 true 才 `animateToPage(240ms, easeOutCubic)`；HUD 进度条跳页同样遵循该开关。
- 双击任意位置：1.0 ↔ 2.2 缩放切换。
- 与手势并存：左滑 = 下一页、右滑 = 上一页（`onHorizontalDragEnd`，阈值 40px）。

**HUD（两模式共用 `reader_hud.dart`）**

| 位置 | 元素 | 行为 |
|---|---|---|
| 顶部 46 高，`blur(20)` + 黑 65% | 左 `back.svg` 退出 · 中「标题 · 第 N/M 页」· 右模式切换图标 | 退出 pop 回详情并写进度；切模式保持阅读位置（按页码比例换算滚动偏移） |
| 底部 64 高，同底色 | 左「已读 12/19」· 中 `Slider` 进度条 · 右「23%」 | 拖动时顶部浮出「第 N 页」气泡；松手 `jumpToPage(n)` 并落库 |
| 隐藏态 | — | 全屏沉浸（`SystemUiMode.immersiveSticky`），点中区恢复 |

**其它约束**

- 预加载 ±2 页；已解码页进 LRU（上限 12 页），evict 时释放 `Uint8List`。
- 切片还原在 isolate 完成；单页失败显示 `alert.svg` + 「重试」，只重试该页。
- 进度记忆：Hive `progress:{albumId}:{chapterId}` → `{page,total,updatedAt}`，切页/退出节流写（≥1s）。
- 首末页边界：第 1 页向右不动，最后一页向左不动；进度条到端点时滑块半透明。

### 7.7 我的

- 顶部资料卡：渐变底 + `user.svg` 占位头像 + 「未登录 · 本地模式」+ 副标题。
- 统计条：下载完成数 / 收藏数 / 阅读历史（均来自 Hive）。
- 设置组一（阅读）：默认阅读模式（左右翻页 / 上下滚动）、翻页动画开关。
- 设置组二（外观）：主题模式（跟随系统 / 浅色 / 深色）。
- 设置组三（网络）：当前线路（`apiHost` + `imgHost`，点击重新探测）、自动切换开关。
- 设置组四（存储）：默认下载目录（可复制）、清理临时文件、清理封面缓存、导出记录。
- 设置组五（关于）：版本、开源许可（`showLicensePage`）、`probe_api.ps1` 排障指引。

### 7.8 下载页

- 输入卡：`TextField(maxLines: 6, minLines: 3)`，hint「每行一个车号，支持 350234 / JM350234 / 链接」；下方「粘贴」「清空」「解析预览：3 个有效 · 1 个忽略」；主按钮「加入队列」。
- 分段筛选：`SegmentedButton`（全部 / 进行中 / 已完成），进行中带计数徽标。
- 任务卡：左封面缩略（48×64）+ 标题 1 行 + 状态胶囊（排队/下载中/已完成/失败/已取消）+ 环形进度（`CircularProgressIndicator` value 驱动）+ 「12/48 页 · 1.2 MB/s」+ 操作（打开 / 取消 / 重试 / 删除，`PopupMenuButton` 收纳）。
- 底部「清空已完成」文字按钮（二次确认 `showDialog`）。
- 空态：插画 + 「输入车号开始下载」+ 「如何获取车号？」折叠说明。

### 7.9 收藏夹（本地账本 + 服务端镜像）

> 完整设计（模型、box、迁移、对账算法、F1–F5 拆分、测试矩阵）见 **`docs/FAVORITES.md`**；这里只留实现时不得偏离的约束。

- **定位**：收藏页永远先渲染 Hive，网络只做对账；服务端只镜像「在不在收藏里」这一个布尔，文件夹/追更/标题快照都是本地能力。
- **入口**：我的 → 统计卡「收藏 N」+ 「我的收藏」行；Dock 仍三档，收藏是二级页（`/collect`）。
- **页面**：顶部「本地收藏 · 登录后可同步」提示条（仅未登录显示）→ 文件夹 chips（全部 / 默认 / 自建 / + 新建）→ 排序 chips（收藏时间 `mr` / 更新时间 `mp`）+ 视图切换 → 三列网格 → 多选批量条（移动 / 下载 / 移除）→ 触底加载每页 20、切排序回顶。
- **卡片角标**：待同步（点）/ 已同步（云）/ 纯本地（无）/ 有更新（橙点，`updateAt > lastSeenAt`）。
- **写路径**：乐观更新 + 180ms 缩放 + SnackBar「已收藏 · 撤销 / 查看」；撤销同时删除对应 outbox 项，别把撤销同步出去。
- **接口**：`GET /favorite?page&o&folder_id=0`、`POST /favorite {aid}`（**toggle**，返回 `type` 与预期不符必须反向补发一次并标 conflict）、`POST /login`（存 cookie + `AVS`，**不存明文密码**）、上限取 `album_favorites_max`。
- **限流**：push 串行、间隔 ≥400ms、退避 2s/8s/30s（最多 5 次）；对账翻页间隔 ≥300ms；连续 3 条业务失败暂停本轮。
- **迁移**：老的 `jm_favorites = {ids:[…]}` 必须在启动时迁成 per-album 记录，空标题惰性补详情，不阻塞首屏。
- **不取 jm-mobile 的做法**：明文存密码做自动登录；也不做服务端收藏夹创建/改名（接口未验证）。
- **验收**：断网可收藏/取消/切文件夹/排序/删除；登录后本地与服务端双向一致；toggle 被反向时自愈；上限 90% 起告警。

### 7.10 会话与登录（收藏同步的前置）

> 完整解剖（jm-mobile 的拦截器链、自动登录、登出、UI 细节）与我们的实现骨架见 **`docs/FAVORITES.md` §2 / §4**。

- **定位**：cookie 为主、`/login` 换取账号信息为辅；**不存明文密码**（jm-mobile 存明文并在每次冷启动重登，我们不取）。
- **存储**：新 box `jm_session` 只放会话快照 + cookie 列表（含 `AVS`）；密码若要记住，必须用户显式勾选并落 `flutter_secure_storage`。
- **拦截器链顺序**：`SessionGate`（`/setting`、`/login` 放行）→ `Endpoint`（域名轮换）→ `Token`（**每请求现算** `md5(ts+secret)`，版本取 `/setting.jm3_version`）→ `Cookie` → `Decrypt`（`{code,data}`，**AES-256-ECB**）→ `LoginRequired`（401/HTML/`code!=200` → `needsLogin`）。
- **登录时序**：`bootstrap()` → `POST /login`（multipart）→ 响应带 `s` 就补写 `AVS` cookie → `UserSession(state: valid)` → `GET /favorite?page=1` 校验 → **登录成功立即做一次双向收藏同步**（先对账把云端拉回本地，再推 outbox 把本地补到云端），结果在提示框里报「云端 N 本 · 拉回 M 本 · 上传 K 本」。
- **失败提示**：登录失败必须是对话框（图标 + 原因 + 排查提示 + 「重试」），不能只在输入框下塞一行红字；原因归一化：密码错 / 被限流 / 人机校验 / 线路异常四类文案。
- **自动登录**：默认「cookie 恢复 + 一次校验」，失败一次即回 `local`，不打扰用户；不做每冷启动重登。
- **失效**：`needsLogin` 时收藏继续本地可用，我的页顶栏给「登录已失效 · 重新登录」，只重试一次（仅当开启记住密码）。
- **登出**：session + cookie + outbox 三处清空；本地收藏保留但 `synced → localOnly`，避免推到下一个账号。
- **UI**（对齐 jm-mobile 的可抄部分）：用户名/密码 ASCII-only 过滤、用户名失焦 trim、IME Next/Done、按钮 loading「登录中」、成功后 `popUpTo` 不留在栈里。

### 7.11 互动：点赞与评论（0.3.0）

> 端点实测与字段表见 §5.4 #14–#16；完整契约、失败矩阵与测试用例见 **`docs/INTERACTION.md`**。

- **模型**：`JmComment`（`CID/UID/username/nickname/likes/addtime/parent_CID/content/photo/spoiler/replys[]`）+ `JmCommentPage`（`items/total/page`，`hasMore(pageSize:20)`）；`addtime` 兼容秒级时间戳与 `yyyy-MM-dd HH:mm:ss`，展示成「刚刚 / N 分钟前 / N 小时前 / N 天前 / MM-DD」。
- **点赞**：`POST /like` multipart `id=<专辑 id>`，响应是**明文** `{code,msg,status}`（不在 AES 信封外层语义里，但仍在 `data` 内）；无计数、无取消接口 → 客户端乐观 `likes + 1` 并锁成「已点赞」。状态源：`/album.liked`、`/album.likes`。
- **评论列表**：`GET /forum?page&aid&mode=manhua`，游客可读；空结果 `{list:[],total:"0"}`；发评论后回第 1 页（新评论在前）。
- **发评论**：`POST /comment` multipart `comment/aid/status/comment_id`；`status='1'` 表示剧透；**未登录返回 401**，客户端在请求层把 401 归一到 `JmContentException('登录状态已失效，请重新登录')`，UI 弹「登录后才能操作 → 去登录」，不静默失败。
- **登录门槛**：点赞、发评论、回复都必须已登录；收藏不同（本地可用，见 §7.9）。
- **不做**：评论点赞、删评论、举报、通知未读数 —— 接口未验证，宁缺不猜。
- **限流**：评论与点赞都是用户手动触发，不做自动重试；失败只提示，避免重复发帖。

---

## 8. 下载引擎移植规格（基准 `D:\data\coding\JmScript`）

### 8.1 对照表（Kotlin → Dart）

| JmScript 源文件 | 目标文件 | 必须保持的行为 |
|---|---|---|
| `data/JmApiClient.kt` | `data/sources/jm_api_client.dart` | 线路轮换 / 最优 host 置顶 / cookie 复用 / 图床切换 / 返回 HTML 视为失败 |
| `data/JmCrypto.kt` | `data/sources/jm_crypto.dart` | token、AES-ECB、MIME Base64 容错 |
| `data/JmResponseParser.kt` | `data/sources/jm_response_parser.dart` | 章节按 `sort` 升序 + 同 `sort` 去重 + 空 `series` 退化为单章；`images` 空 → 抛「没有可下载的图片」 |
| `image/ImageScrambler.kt` | `core/image/image_scrambler.dart` | §5.7 段数算法，一字节不差 |
| `image/ImageProcessor.kt` | `core/image/image_processor.dart` | 还原切片 → 重编码真 PNG；失败时删除目标文件 |
| `export/PdfExporter.kt` | `features/download/engine/pdf_exporter.dart` | 1 页 1 图；页尺寸=位图尺寸；长边 > 14400 等比缩放；白底 |
| `export/DocumentsPdfStore.kt` | `features/download/engine/pdf_sink.dart` | `Documents/JMComics/`；同名 → `名称 (2).pdf`；先 `IS_PENDING` 后转正（Dart 侧：先写 `.part` 再 rename） |
| `download/DownloadSlots.kt` | `download_slots.dart` | 队列级并发 3 |
| `download/DownloadCoordinator.kt` | `download_coordinator.dart` | 入队去重、取消、重试、清空已完成 |
| `download/JmDownloadWorker.kt` | `download_worker.dart` | 流水线 + 进度节流 + IO 重试 ≤2 + OOM/尺寸提示清理 |
| `history/DownloadRecord.kt` / `HistoryStore.kt` | `data/models/download_record.dart` + `data/local/download_store.dart` | 状态机与字段全对齐 |
| `util/FileNames.kt` | `core/utils/file_names.dart` | 非法字符 → `_`、空白折叠、去首尾 `.`、码点截断 80、空标题 `comic` |
| `util/JmIdParser.kt` | `core/utils/jm_id_parser.dart` | §5.8 语义 + 批量分词去重保序 |
| WorkManager 前台任务 | `notification_service.dart`（`flutter_foreground_task`） | 后台继续跑 + 通知进度 + 取消动作 |
| `HistoryActivity` / `MainActivity` | `features/download/*` | 输入、卡片、飞入动画（可用 `Overlay` + `AnimationController` 轻量实现） |

### 8.2 单任务流水线

```
1. 取槽位（队列并发 3）
2. ensureRecord(albumId) → state=RUNNING, status="正在连接 JM 服务"
3. api.prepare()（复用既有 client 与 cookie）
4. album = api.getAlbum(albumId)
     若 series_id 非 "0" 且 ≠ id → 以 series_id 重取一次
5. 预取全部章节清单：for ch in album.chapters → api.getChapter(ch.id)
     得到 [(photoId, title, images[])]；total = Σ images.length
     状态更新为 "准备完成 N 页"
6. 逐章：scrambleId = api.getScrambleId(photoId)   // 同 album 可缓存
      逐页（单任务并发 3）：
        bytes = api.downloadImage(photoId, filename)   // 含图床轮换
        png   = ImageProcessor.toPng(bytes, scrambleId, photoId, filename)  // isolate
        写 workDir/{全局页序:05d}.png
        进度：done++, percent = done/total*100（节流 ≥1s 或状态变迁才落盘）
7. pdf = PdfExporter.export(sorted pagFiles)
8. name = FileNames.pdfName(albumId, album.title)
   pdfSink.write(name, pdf)   → Documents/JMComics/JM123 - 标题.pdf
9. state=SUCCEEDED, pdfPath/pdfName/pageCount 落库
10. finally: 删除 workDir（成功/失败/取消都删）
```

### 8.3 状态机与字段（与 Kotlin 一致）

```dart
enum DownloadState { queued, running, succeeded, failed, cancelled }

class DownloadRecord {
  final String workId;      // 唯一任务 id（时间戳+随机）
  final String albumId;
  final String title;
  final DownloadState state;
  final String status;      // 面向用户的一句话，如「已下载 12/48 页」
  final String detail;      // 次要信息：当前线路 / 错误原因
  final int done, total, percent;
  final String? pdfPath;    // 落盘绝对路径
  final String? pdfName;
  final int pageCount;
  final String? error;
  final int createdAt, updatedAt;
}
```

- 落盘节流：`percent` 变化 ≥1，或 `state/status` 变化，或距上次写 ≥1000ms。
- 重试：任务级 IO 异常 ≤2 次（`state` 回 `queued`，`status="连接失败，正在自动重试"`）；超过则 `failed` 并带 `error`。
- 取消：`coordinator.cancel(workId)` → 置 `cancelled`、停信号量等待者、删除 workDir；已导出的 PDF 保留。
- 去重：同 `albumId` 已有 `queued/running` 时，第二次入队直接返回既有任务并提示「已在队列中」。

### 8.4 PDF 导出（Dart 版要点）

```dart
// 一页一图；页尺寸 = 图像像素尺寸（1px = 1pt）；长边上限 14400pt；白底
final document = pw.Document();
for (final file in orderedPngFiles) {
  final bytes = await file.readAsBytes();
  final decoded = img.decodeImage(bytes);            // package:image，失败返回 null
  final w = decoded?.width ?? 1200;
  final h = decoded?.height ?? 1800;
  final scale = math.min(1.0, 14400.0 / math.max(w, h));
  final pageFormat = PdfPageFormat(w * scale, h * scale, marginAll: 0);
  document.addPage(pw.Page(
    pageFormat: pageFormat,
    build: (_) => pw.Container(
      color: PdfColors.white,
      child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.contain),
    ),
  ));
}
final pdfBytes = await document.save();
```

注意：`pw.MemoryImage` 只吃 PNG/JPEG 字节；`image` 包解不出的格式（如 AVIF）在落盘前先转 PNG，转不了就跳过该页并计入 `detail`。

- `image` 包解不出的格式（AVIF 等）：保留原始字节；若为 JPEG 直接 `pw.MemoryImage(bytes)`；两者都不成 → 该页记失败并继续，最终在 `detail` 里报「3 页解码失败」。
- 导出目录：`getExternalStorageDirectory()` 下的 `JMComics/` 作为暂存，最终 `media_store_plus` 写入公共 `Documents/JMComics/`；插件失败 → 留在 app 外部目录并把路径写进 `pdfPath`。

---

## 9. 实施阶段（M0–M6，逐卡验收）

### M0 环境与空壳（半天）

```powershell
# 1) 装 Flutter stable（约 1.2 GB，含 Dart）
git clone -b stable --depth 1 https://github.com/flutter/flutter.git D:\data\tools\flutter
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path

# 2) 绑定 Android SDK 并体检
flutter config --android-sdk C:\Users\Jolie\AppData\Local\Android\Sdk
flutter doctor -v
flutter doctor --android-licenses   # 全 y

# 3) 生成工程（当前目录已存在 PLAN.md 等文件，会被保留）
cd D:\data\product\JMComic
flutter create --org com.jmcomic --project-name jm_comic --platforms android,ios .

# 4) 依赖 + 静态检查
flutter pub get
flutter analyze
```

- `android/app/build.gradle.kts`：`minSdk = 29`、`compileSdk = 35`、`targetSdk = 35`。
- `AndroidManifest.xml`：`INTERNET`、`POST_NOTIFICATIONS`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`、`WAKE_LOCK`；`android:usesCleartextTraffic="false"`。
- 图标与插画已就绪：`assets/icons/*.svg`（22 个）+ `assets/illustrations/*.svg`（3 个），`pubspec.yaml` 里按 §3.1 声明三个目录；`lib/core/icons/app_icons.dart` 写常量表 + `SvgIcon`。
- 验收：改 `lib/main.dart` 为三 tab 空壳 + 玻璃 Dock（图标走 `SvgIcon`），可 `flutter run` 到模拟器/真机；`pwsh -File .\tools\check_ui_rules.ps1` 通过。

### M1 协议层（1 天）

- 实现 `jm_constants` / `jm_crypto` / `jm_endpoint_resolver` / `jm_api_client` / `jm_response_parser` + 模型。
- `test/data/jm_crypto_test.dart`、`test/core/jm_id_parser_test.dart`、`test/core/file_names_test.dart`、`test/data/jm_response_parser_test.dart`（向量见 §10）。
- 验收：`flutter test` 绿；`flutter run` 里加一个临时按钮，点一下打印 `imgHost / promote 模块数 / 第一页 80 条`。

### M2 首页（1.5 天）

- `HomeRepository` + `homeFeedProvider`（`AsyncNotifier`，含 `refresh()` / `loadMore()`）+ 首页 UI + 骨架 + 缓存。
- `test/features/home_repository_test.dart` 用 `http_mock_adapter` 回放 `test/fixtures/*.json`。
- 验收：真机首页 4 类区块齐全、翻到第 3 页、断网先出缓存。

### M3 搜索 + 详情 + 阅读器（1.5 天）

- `searchPage`：`resolveQuery()` 判定（车号 → 直推详情；关键词 → GET `/search`）+ 历史 + 结果网格 + 空态。
- `albumPage`：封面模糊头 + 章节列表 + 底部「开始阅读 / 下载」双 CTA。
- `readerPage`：`ReaderMode` 双实现——`page_turn_view`（左右翻页 + 三分区点击 + HUD）与 `scroll_reader_view`（上下滚动）；切片还原 + LRU + 进度记忆。
- 验收：搜 `350234` 直达详情；搜「中文」出结果并可翻页；阅读器两种模式可切，点左/中/右行为符合 §7.6，退出再进恢复页码。

### M4 下载引擎（2 天，重点）

- `download_task` / `download_slots` / `download_worker` / `pdf_exporter` / `pdf_sink` / `notification_service` / `download_coordinator`。
- `test/download/image_scrambler_test.dart`、`image_processor_test.dart`（用 `test/fixtures/slice_sample.png` 合成切片图）、`pdf_exporter_test.dart`（生成 2 页 PDF 断言页数）。
- 验收：输入 3 个车号 → 3 并发 → `Documents/JMComics/` 出 3 个 PDF；再来一次出现 `(2)`；取消后 workDir 为空。

### M4.5 登录与收藏（1.5 天）

- **F0 会话**：`UserSession` / `SessionStore`（`jm_session`）/ `AuthRepository` / 拦截器链改造 / 登录页 —— 验收：能登录、杀进程后仍登录、登出三处皆清、`AVS` 写入正确。
- **F1–F3 收藏**：`FavoriteItem` + 迁移 + 收藏页 + 详情联动（详见 §7.9 与 `docs/FAVORITES.md` §9）。
- **F4–F5 同步与批量**：对账 + outbox + 退避 + 上限 + 多选批量 + 追更角标。
- 验收：见 `docs/FAVORITES.md` §10 的 15 条测试矩阵，登录/失效/登出/断网四条必须有真机 case。

### M4.6 互动与体验收尾（1 天，0.3.0）

- **点赞 / 评论**：`/like`、`/forum`、`/comment` 三层打通（模型 → API → 仓储 → provider → UI），详情页动作条与评论区（展开/翻页/写评论/剧透/回复）。
- **登录**：失败对话框（原因归一化）+ 登录成功自动双向同步（`favoritesSyncProvider.syncNow()`），同步结果在成功框里给出统计。
- **阅读器**：双模式双指缩放 + 双击放大；`pageTurnAnimation` 开关真正生效（关=瞬切）。
- **首页**：标签页内存缓存（5 分钟 TTL）+ 空闲预热 3 个分类，切回不闪骨架屏。
- **视觉**：收藏图标从书签换成五角星（`star.svg` / `star-filled.svg`），点赞用爱心，首页 AppBar 品牌标记改用 `img/brand/brand.png` 切出的 `brand_logo.png`。
- 验收：`flutter analyze` 0 issue、`flutter test` 全绿、`tools/check_ui_rules.ps1` 通过；真机手测：登录 → 点赞 → 发评论 → 收藏 → 同步一轮闭环。

### M5 我的（0.5 天）

- 设置项全部接真（主题即时生效、清缓存统计字节数、线路展示与重新探测）。
- 验收：杀进程重启，主题/记录/统计保持。

### M6 打磨与发布（1 天）

```powershell
flutter analyze
flutter test
flutter build apk --release --dart-define=APP_FLAVOR=prod
# 产物：build\app\outputs\flutter-apk\app-release.apk
```

- 逐项过 §2.2 验收清单；真机（Android 12/13/14 任一）冷启动 ≤2s、首页首屏 ≤1.5s、下载 20 页 ≤60s（4G）。

---

## 10. 测试计划

### 10.1 必须固化的向量（抄自 `JmScript` 单测，全部通过才算移植成功）

**token**

| 输入 ts | 期望 token |
|---|---|
| `1700566805` | `cce2cb071cd0cf371a2e34fd5ad66fd6` |

**AES 解密**：`ts=1700566805`，明文 `{"name":"Test Comic","id":123}` → 用同一 key 加密 → 解密回原文（往返一致）。

**切片段数**（`scrambleId=220980`）

| photoId | filename | 期望段数 |
|---|---|---|
| 100 | `00001.webp` | 0 |
| 220980 | `00001.webp` | 10 |
| 268850 | `00001.webp` | 6 |
| 268850 | `00002.webp` | 4 |
| 421926 | `00001.webp` | 14 |
| 421926 | `00002.webp` | 12 |
| 421926 | `/photos/00001.webp?v=1` | 14 |
| 350234 | `00001.webp` | 2 |

**车号解析**

| 输入 | 期望 |
|---|---|
| `350234` / `JM350234` / `jm 350234` / `车号：350234` | `350234` |
| `https://18comic.vip/album/350234/` | `350234` |
| `https://18comic.vip/photo/438516/` | `438516` |
| `https://example.test/album/?id=350234` | `350234` |
| `JM000123` | `123` |
| `` / `JM` / `0` / `12345678901` | `null` |

批量：`"350234\nJM350235, 350236，350237"` → `[350234,350235,350236,350237]`；`"JM350234 350234 https://18comic.vip/photo/438516/"` → `[350234,438516]`；`"350234\nJM\nabc"` → `[350234]`（分词后 3 段）。

**文件名**

| 输入 | 期望 |
|---|---|
| `pdfName("123", "  Test:\n/Comic  ")` | `JM123 - Test___Comic.pdf` |
| `pdfName("123", "...")` | `JM123 - comic.pdf` |
| `pdfName("123", "😀"*100)` | 标题截断到 80 个码点（emoji 不裂） |

**专辑/章节解析**

| 场景 | 期望 |
|---|---|
| `series` 顺序 `[sort2,sort1,sort2]` | 章节 id 顺序 `[101,102]`（升序 + 同 sort 去重） |
| `series: []` + `id:123` | 单章 id `123` |
| `images: []` | 抛 `JmContentException` |
| `images: ["00002.webp","00001.webp"]` | 顺序保持原样（不重排） |

### 10.2 fixtures

`test/fixtures/` 需落：`setting.json`、`promote.json`、`latest_p1.json`、`categories.json`、`filter_p1.json`（均可由 `tools\probe_api.ps1` 输出改写）；`home.html`（HTML 兜底用）；`slice_sample.png`（人为切片后用于还原断言）。

### 10.3 widget / 集成

- `shell_page_test.dart`：点 Dock 三项 → 三个页面各自出现，切走再回，`scrollController.offset` 保持。
- `home_page_test.dart`：mock provider 返回固定 `HomeFeed` → 断言轮播/分节/网格渲染数量；空态与错误态各一。
- `search_flow_test.dart`：`resolveQuery('350234') → id` 走详情路由；`resolveQuery('中文') → keyword` 触发 `/search`（`http_mock_adapter` 断言 query 参数与页码）；空输入不发请求。
- `reader_test.dart`：翻页模式下点右 1/3 `page+1`、点左 1/3 `page-1`；点中 1/3 HUD 显隐；`Slider` 拖动到 12 → 顶部气泡显示「第 12 页」；退出后 `progress:` 键落库；模式切换后页码保持。
- `ui_rules_test.dart`：跑 `tools\check_ui_rules.ps1` 的等价 Dart 断言（或 CI 步骤）——`lib/` 内无 emoji、无 `Icons.`。
- `download_flow_test.dart`：mock client 返回 2 章 × 3 页 → 断言记录从 queued → running → succeeded，`pageCount == 6`，命名正确。
- 真机 smoke：`flutter run --profile` + 手工跑一遍 §2.2 清单。

---

## 11. 失败模式与兜底

| 现象 | 处理 |
|---|---|
| 内置 API 域名全挂 | 域名发现重试 3 源；仍失败 → 我的→网络→手动填域名（持久化） |
| `/setting` 拿不到 cookie | 后续接口会被重定向成「禁漫娘」页面 → 请求前比对响应是否 JSON，非 JSON 就重新 `prepare()` 一次 |
| `img_host` 漂移 | 每次冷启动 `prepare()` 刷新；`img_host` 变化清掉 `cached_network_image` 的 URL 前缀缓存键 |
| 图床返回 HTML / 502 | 检测 `content-type`，换下一图床（最多 6 个）；全失败 → 该页失败计数 +1，≥3 页失败则任务 `failed` |
| 大图 OOM | `image` 在 isolate 内解码；`MAX_PAGE_EDGE=14400`；单页处理完立刻释放 `Uint8List`；捕获 `OutOfMemoryError` 转「图片尺寸过大」 |
| AES 解密异常 | 先试原样、再去空白、再补 `=`；仍失败按 `code + errorMsg` 抛 `JmContentException`，在 UI 显示可读原因 |
| `total=10000` 看似无限 | 视为服务端上限；`content` 为空页即终止分页 |
| 公共 Documents 写不进 | 降级 app 外部目录 + `open_filex` 分享；记录里存两个路径，UI 提示「已存至应用目录」 |
| 通知权限被拒（Android 13+） | 下载照常跑，仅无进度通知；下载页顶部给一条可点开的提示条 |
| 前台服务被杀 | 任务落库为 `running`，下次启动扫描到「僵尸 running」→ 标记 `failed`（`error="进程被系统回收"`）并允许一键重试 |
| HTML 改版 | 选择器集中常量 + fixture 回归；失败自动回落 API（或缓存） |
| 本机代理导致全线路 TLS 握手失败 | 本机系统代理为 `FlClash 127.0.0.1:7890` 且处于开启状态；**PowerShell 与 dart:io 默认都不读 WinINET 代理**。`probe_api.ps1` 已自动读注册表补 `-Proxy`；App 侧 `dio_factory` 支持 `--dart-define=JM_PROXY=http://127.0.0.1:7890`，在 Dio 初始化时 `httpClientAdapter`/`HttpClient.findProxy` 注入；真机走 TUN 模式即可 |

---

## 12. 工具脚本

```powershell
# 目录脚手架（幂等）
pwsh -File .\tools\scaffold.ps1

# 协议实网自检（线路 / promote / latest / categories / filter / album / chapter / scramble / 封面 / 正文图）
pwsh -File .\tools\probe_api.ps1
pwsh -File .\tools\probe_api.ps1 -ApiHost www.cdnutc.cc -AlbumId 350234
```

`probe_api.ps1` 输出全绿即代表本机网络与站点协议正常，可开始 M1；任何一段红先换 `-ApiHost`。
一次全绿的真实输出已留档：`docs\PROBE_RESULT_2026-11-14.txt`（可直接作为 `test/fixtures/*.json` 的结构参照）。

> 本机网络注意：系统代理为 FlClash `127.0.0.1:7890`，PowerShell 默认不读 WinINET 代理，脚本已自动补 `-Proxy`；代理节点波动时会出现「全线路 TLS handshake 失败」，换节点或改用手机热点后重跑即可，与脚本逻辑无关。

---

## 13. 假设与开放项

1. **平台范围**：本轮只验收 Android；iOS 目录保留、不验收（`media_store_plus`、前台服务在 iOS 需另做）。
2. **不改参考项目**：`D:\data\coding\JmScript` 只读；不采用其 `JM-PDF-Downloader-1.0.2-debug.apk`。
3. **登录体系**：`/login`、`/favorite`、`/daily` 等接口已知存在，但 v1 只做本地态（收藏存 Hive、无签到/充值/评论）。接入登录时按 §5.3 同一套加解密＋cookie 会话即可。
4. **Phase 7（可选）**：若 Dart `image` 包在极端图片上表现不足，把 `JmScript` 的 `ImageProcessor`/`PdfExporter` 抽成 Android library，用 `MethodChannel` 直连；接口签名需保持与 `core/image/image_processor.dart` 一致，便于无痛切换。
5. **文案语言**：中文为主；`l10n` 仅留骨架。
6. **协议时效**：站点域名与字段会变。任何协议争议以 `tools\probe_api.ps1` 的实时输出为准，改动同步记到 `docs/`。

---

## 14. 交接自检（接手方开工前跑一遍）

```powershell
cd D:\data\product\JMComic
Get-ChildItem -Recurse -Directory lib | Select-Object -ExpandProperty FullName   # 27 个目录应齐全
Get-Content .\PLAN.md -TotalCount 5
pwsh -File .\tools\probe_api.ps1                                                  # 全绿再动手
flutter --version                                                                 # 未装 → 先做 M0
```

按 §9 顺序推进即可；每个里程碑结束都跑一次 `flutter analyze && flutter test`，不要攒到最后。
