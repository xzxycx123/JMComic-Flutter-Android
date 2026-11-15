# JMComic Flutter 客户端

首页浏览（JM 移动端接口）+ 本地 PDF 下载（移植自 `D:\data\coding\JmScript`）的 Flutter 应用。
底部 Dock 三档：**首页 / 我的 / 下载**。

完整施工方案、协议规格、UI 规格、下载引擎移植对照、里程碑与测试向量 → **[PLAN.md](PLAN.md)**。
本轮落地情况、与 PLAN 的差异 → **[docs/IMPLEMENTATION.md](docs/IMPLEMENTATION.md)**。

## 构建（本机已装 Flutter 3.50.0 / Dart 3.14.0）

SDK 位置：`D:\data\tools\flutter`（stable，已绑定 `C:\Users\Jolie\AppData\Local\Android\Sdk`）。
`android/`、`ios/` 已由 `flutter create --org com.jmcomic --project-name jm_comic` 生成，`apply_android_config.ps1` 也已跑过。

```powershell
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path
# 必须用 64 位 JDK：本机默认 java 是 32 位 Liberica（Gradle 起 4G 堆会失败）
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.4'
cd D:\data\product\JMComic

python tools\build_app_assets.py   # img/ -> assets/images + mipmap 图标（幂等）
flutter pub get                    # 已解析 117 个依赖
flutter analyze                    # No issues found
flutter test                       # 75 个用例全绿

flutter build apk --release
# 产物：build\app\outputs\flutter-apk\app-release.apk（universal，62.6 MB）
# 已归档：dist\JMComic-0.1.0-release.apk（SHA256 E2B2D8CA…F9943F6B）
# 瘦身可加 --split-per-abi（按 ABI 拆包，单包约 20 MB）

# 装到已连接设备：
adb install -r dist\JMComic-0.1.0-release.apk
```

构建环境说明（本机踩过的坑，换机器同样适用）：

- **JDK**：必须 64 位；32 位 JVM 会报 `Invalid maximum heap size: -Xmx8G/4G`。
- **compileSdk = 36**：Flutter 3.50 的插件默认按 36 编译，只用 35 会触发 `plugin compiles against 36` 校验失败；`tools\apply_android_config.ps1` 已按 36 写死（minSdk 29 / targetSdk 35 不变）。
- **Gradle 代理**：`C:\Users\Jolie\.gradle\gradle.properties` 里配 `systemProp.https.proxyHost=127.0.0.1` + `proxyPort=7890`（本机 FlClash）；否则 Maven Central 会 `Remote host terminated the handshake`。
- **Kotlin 增量编译**：pub cache 在 C:、工程在 D: 时 Kotlin 2.4 会报 `this and base files have different roots`，`android/gradle.properties` 已设 `kotlin.incremental=false` + `kotlin.incremental.useClasspathSnapshot=false`。

首次在新机器重建时：

```powershell
git clone -b stable --depth 1 https://github.com/flutter/flutter.git D:\data\tools\flutter
flutter config --android-sdk C:\Users\Jolie\AppData\Local\Android\Sdk
flutter doctor --android-licenses
sdkmanager "platforms;android-36"
flutter create --org com.jmcomic --project-name jm_comic --platforms android,ios .
pwsh -File .\tools\apply_android_config.ps1
python tools\build_app_assets.py
```

> 如果 `flutter` 首次运行卡在 “Downloading Dart SDK”（BITS 不走代理）：手动
> `curl -L --proxy http://127.0.0.1:7890 -C - -o bin\cache\dart-sdk-windows-x64.zip https://storage.googleapis.com/flutter_infra_release/flutter/<engine.stamp>/dart-sdk-windows-x64.zip`
> 解包到 `bin\cache\dart-sdk`，并把 `engine.stamp` 的内容写进 `bin\cache\engine-dart-sdk.stamp`。

## 工具脚本

```powershell
pwsh -File .\tools\scaffold.ps1              # 幂等目录脚手架
pwsh -File .\tools\probe_hosts.ps1           # 线路发现 + 实测 → assets/data/jm_hosts.json + docs/NETWORK_DOMAINS_<date>.md
pwsh -File .\tools\probe_api.ps1             # 协议实网自检（线路 / promote / latest / ... / 图床）
pwsh -File .\tools\check_ui_rules.ps1        # UI 守卫：禁 emoji、禁 Icons.*、图标必须 SVG
pwsh -File .\tools\apply_android_config.ps1  # flutter create 之后应用 android 配置
python tools\build_app_assets.py            # 从 img/ 派生 assets/images + 桌面图标
```

## 目录速查

| 路径 | 说明 |
|---|---|
| `docs/NETWORK_MODULE.md` | 网络模块设计：多源发现、连通性探测、健康度/冷却、国内域名清单 |
| `docs/NETWORK_DOMAINS_<date>.md` | 最近一次全量实测留档（`tools\probe_hosts.ps1` 生成） |
| `assets/data/jm_hosts.json` | 打进 APK 的线路种子（api / image / web 三组，含延迟与时间戳） |
| `PLAN.md` | 交接文档（协议 / UI / 移植 / 里程碑 / 测试向量） |
| `docs/ui-draft.html` | **UI 交互草稿**：六屏可点原型 + 25 个按钮编号 + 行为/接口对照表 |
| `docs/ui-draft*.png` | 草稿截图（首页 / 搜索 / 详情 / 阅读器 / 下载 / 我的） |
| `docs/PROBE_RESULT_2026-11-14.txt` | 一次全绿的接口探测留档 |
| `assets/icons/*.svg` | 全部 UI 图标（自绘 24×24 / stroke 1.75），规则见 `assets/README.md` |
| `lib/core` | 主题、路由、Dio、图片算法、工具、依赖注入 |
| `lib/data` | 模型、协议源（crypto/api/scraper/parser）、本地存储、仓储 |
| `lib/features` | shell（三 tab）、home、album、reader、mine、download |
| `lib/features/download/engine` | 下载引擎（对照 `JmScript` 的 Kotlin 实现） |
| `test` | 单元 + widget 用例，fixtures 用 `tools\probe_api.ps1` 的真实结构改写 |

## 关键事实（实测，2026-11-14，2026-11-15 复核）

- token = `md5hex(ts + "185Hcomic3PAPP7R")`；响应 `data` 用 **AES-256-ECB/PKCS7**、key = `ASCII(md5hex(ts + secret))` **全部 32 字节**解密（旧文档写的 16 字节是错的，见 §协议更正）。
- 线路：内置种子 `assets/data/jm_hosts.json` → TOS 域名服务（`newsvr-2025.txt`，AES-256 + 空 ts）→ 发布页 `jmcomictt.site / jmcomicgo.org`（国内域名）→ GitHub 镜像配置；实测 ok 的按延迟排序，失败进 10 分钟冷却。
- 国内地址（发布页「內地 / 分流」）：`comic18j-susu.com`、`comic18j-nico.work`、`comic18j-neo.com`。**不提供 APP 接口**（`/setting` 404、网页被 Cloudflare 挑战），但 `/media/...` 能直出图片 → 作为国内图床兜底。
- `/promote`（8 模块）、`/latest`（80/页）、`/categories`、`/categories/filter`（80/页）**直接可用**，首页无需依赖 HTML 解析。
- 列表接口 `image` 字段恒空 → 封面自拼：`https://{img_host}/media/albums/{id}_3x4.jpg`（实测 200）。
- 正文图：`https://{img_host}/media/photos/{photoId}/{filename}`；切片阈值来自 `/chapter_view_template` 的 `scramble_id`。
- 本机代理：`--dart-define=JM_PROXY=http://127.0.0.1:7890`（FlClash），真机走 TUN 即可。
