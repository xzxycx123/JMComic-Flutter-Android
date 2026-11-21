# JMComic for Android

一个 Android 优先、**本地优先**的 JM 客户端：首页浏览、搜索、阅读器、PDF 下载归档，以及登录后可双向同步的收藏夹，且拥有LiquidGlass主题
（主要是JM官方的太丑太卡了，所以重做了一个）

> 本项目是非官方第三方客户端，与站点运营方无关；所有内容版权归原作者与站点所有，本客户端仅做浏览与个人离线备份，不提供内容源、不绕过任何付费/权限。
> 仅支持 Android 8.0+（minSdk 29）。iOS 目录保留但未验收。

[![Flutter](https://img.shields.io/badge/Flutter-3.50-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.14-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android)](https://developer.android.com)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue)](LICENSE)

---

## 功能

| 模块 | 说明 |
|---|---|
| 首页 | 轮播 + 分类 chips + 可折叠排序（最新/日榜/周榜/月榜/人气）+ 无限流；本子封面显示紧凑标签与点赞数；**标签页内存缓存 + 空闲预热**：点回已看过的分类立刻出内容，超过 5 分钟才在后台静默刷新 |
| 搜索 | 纯车号直达详情；关键词走 `/search` 分页，结果支持**按时间 / 阅读数 / 人气 / 最新上架排序** |
| 详情 | 模糊封面头显示 JM 号、紧凑标签、作者点击搜索、章节列表、点赞、评论过滤与相关推荐；双 CTA（继续阅读 / 下载）采用药丸形 |
| 评论 | 默认隐藏包含超过两个 emoji 的疑似广告评论；展开并滑到底后可手动显示这些评论 |
| 阅读器 | 上下滚动 / 左右翻页双模式，三分区点击（符合电子书设计）、阅读进度条；退出（含系统返回）可靠记录最后阅读页，详情页显示「继续阅读」 |
| 下载 | 批量车号 → 队列（3 并发）→ 切片还原 → PNG → PDF，落到 `Documents/JMComics/`；**下载完可直接在 App 内阅读**；LiquidGlass 下任务列表使用清晰的实色内容表面 |
| 账号 | 会话 cookie + **记住密码（系统密钥库）自动重登**：cookie 每次响应后回写、冷启动先跑 `/setting` 再校验，失效时用保存的密码静默重登一次；登录成功即**自动双向同步收藏** |
| 每日签到 | 本地离线签到、月历切换、今天与已签日期标记、本月/累计/连续签到统计，重复签到幂等 |
| 其它 | 深浅主题、线路健康度与测速、本地搜索历史、LICENSE：GPL-3.0 |
| 主题 | Android 原生 Metal 主题和 LiquidGlass 主题；玻璃仅用于导航与浮动控制，滚动内容采用 solid/实色表面 |

---

## 截图

**0.3.3 实机截图**（Android 15），原图见 [`ref img/`](<ref img/>)。

| 搜索（排序：最新更新 / 阅读数 / 人气 / 最新上架） | 详情（统计 / 评论区 / 相关推荐） | 阅读器（HUD 进度条） |
|---|---|---|
| ![](<ref img/SnowShot_2026-11-20_21-43-06.png>) | ![](<ref img/SnowShot_2026-11-20_21-44-46.png>) | ![](<ref img/SnowShot_2026-11-20_21-47-36.png>) |

> 文字说明见 [`docs/INTERACTION.md`](docs/INTERACTION.md)，本版变更与 Release 页文案见 [`docs/RELEASE_README.md`](docs/RELEASE_README.md)。

---

## 下载安装

1. 打开仓库的 **Releases** 页，下载最新 `JMComic-0.4.1-release.apk`；源码构建的产物也会归档到 [`dist/`](dist/)；
2. 允许「安装未知来源应用」后安装（APK 使用 debug keystore 签名，仅自用，不上架应用商店）；
3. 首次启动如提示通知权限，建议允许（下载进度通知需要它）。

```bash
adb install -r dist/JMComic-0.4.1-release.apk
```

---

## 从源码构建

### 环境要求

| 组件 | 版本 |
|---|---|
| Flutter | 3.50.0（stable） |
| Dart | 随 Flutter（3.14.0） |
| JDK | **17（必须 64 位）** |
| Android SDK | `platforms;android-36`、`build-tools;36.x`、`platform-tools`、**NDK 28.2.13676358** |
| Gradle | 由 Flutter 模板提供（9.x） |
| 磁盘 | 首次构建约 3 GB（含 Flutter SDK 与 Gradle 缓存） |

> 为什么需要 NDK：依赖里的 `jni`（transitive）带 CMake 原生构建；缺 NDK 会报 `Could not find toolchain file ... android.toolchain.cmake`。

### 一步步构建

```bash
# 1) 拿到代码
git clone https://github.com/xzxycx123/JMComic-Flutter-Android.git
cd JMComic-Flutter-Android

# 2) 检查工具链（缺什么按提示装）
flutter doctor -v
flutter config --android-sdk "$ANDROID_SDK_ROOT"   # Windows 示例：C:\Users\<你>\AppData\Local\Android\Sdk
flutter doctor --android-licenses

# 3) 依赖 + 素材派生（品牌位图 / 桌面图标 / 启动图；脚本需要 Pillow）
flutter pub get
pip install pillow            # 仅素材派生脚本需要
python tools/build_app_assets.py

# 4) 静态检查与测试
flutter analyze
flutter test

# 5) 打包并归档发布产物（macOS / Linux）
flutter build apk --release
mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/JMComic-0.4.1-release.apk

# Windows PowerShell 归档命令：
# New-Item -ItemType Directory -Force dist
# Copy-Item build/app/outputs/flutter-apk/app-release.apk dist/JMComic-0.4.1-release.apk -Force

# 可选：按 ABI 拆包
flutter build apk --release --split-per-abi
```

### Windows 构建注意事项

```powershell
# 必须指定 64 位 JDK 17，否则 Gradle 起 4G 堆直接失败
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.4'
$env:Path = 'C:\path\to\flutter\bin;' + $env:JAVA_HOME + '\bin;' + $env:Path

# Gradle 走代理（国内网络）：写进 %USERPROFILE%\.gradle\gradle.properties
# systemProp.https.proxyHost=127.0.0.1
# systemProp.https.proxyPort=7890

# Kotlin 在「pub cache 在 C:、工程在 D:」时报 different roots：android/gradle.properties 已设
# kotlin.incremental=false
```

常见问题：

| 现象 | 处理 |
|---|---|
| `Android sdkmanager did not install NDK 28.2.13676358` | 用 sdkmanager 或直接下载 `android-ndk-r28c-windows.zip`，解压到 `<SDK>/ndk/28.2.13676358` |
| `cmdline-tools component is missing` | 安装 Android Command-line Tools，解压到 `<SDK>/cmdline-tools/latest` |
| `plugin compiles against 36` | 工程 `compileSdk = 36`，需装 `platforms;android-36` |
| 首次 `flutter` 卡在 Downloading Dart SDK | 手动下载对应 engine 的 `dart-sdk-windows-x64.zip` 放进 `flutter/bin/cache` |

---

## 项目结构

```
lib/
├─ core/       主题、路由、网络（dio + cookie + 线路健康）、图片算法、图标/位图、工具
├─ data/       模型、协议源（crypto/api/catalog/probe/parser）、Hive 存储、仓储（home/album/favorites/auth/…）
└─ features/   shell（两 tab）、home、album、reader、search、mine、download（含 engine）、collect、auth
test/          单元 + widget 测试（252 通过 / 2 实网 skip）+ fixtures
tools/         probe_api.ps1 / probe_forum.ps1 / probe_hosts.ps1 / scaffold.ps1 / apply_android_config.ps1 / build_app_assets.py
docs/          设计文档（NETWORK_MODULE / FAVORITES / INTERACTION）、UI 草稿、审查记录
```



---

## 开发

```bash
flutter run --release                       # 真机
flutter test                                # 单元 + widget
flutter test --dart-define=JM_LIVE=true \
  --dart-define=JM_PROXY=http://127.0.0.1:7890 test/manual/network_live_test.dart   # 实网联调
pwsh -File tools/probe_api.ps1 -Proxy http://127.0.0.1:7890                          # 协议探测
pwsh -File tools/check_ui_rules.ps1                                                  # UI 守卫（禁 emoji / 禁 Icons.*）
```

贡献：欢迎 PR；

---

## 许可证

本项目以 **GNU General Public License v3.0** 发布，版权归 **Copyright (C) 2026 xzxycx** 所有。
全文见 [LICENSE](LICENSE)

主要参考与致谢：
- [JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)（协议字段核对）
- [jm-mobile](https://github.com/Dedicatus546/jm-mobile)（登录/收藏流程参考，GPL-3.0）
- [LiquidGlass项目](https://github.com/sdegenaar/liquid_glass_widgets) （LiquidGlass主题）

