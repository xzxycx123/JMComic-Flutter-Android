# JMComic for Android（非官方 Flutter 客户端）

一个 Android 优先、**本地优先**的 JM 客户端：首页浏览、搜索、阅读器、PDF 下载归档，以及登录后可双向同步的收藏夹。
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
| 首页 | 轮播 + 分类 chips + 排序（最新/日榜/周榜/月榜/人气）+ 无限流；**冷启动先用上次缓存秒开**；**标签页内存缓存 + 空闲预热**：点回已看过的分类立刻出内容，超过 5 分钟才在后台静默刷新 |
| 搜索 | 纯车号（`350234` / `JM350234` / 链接）直达详情；关键词走 `/search` 分页 |
| 详情 | 模糊封面头、章节列表、统计与标签、**点赞按钮**、**评论区（列表 + 发评论 + 剧透标记）**、相关推荐、双 CTA（阅读 / 下载） |
| 阅读器 | 上下滚动 / 左右翻页双模式，三分区点击、HUD 进度、**双指缩放 + 双击放大**、进度记忆；「翻页动画」开关关掉即瞬切 |
| 下载 | 批量车号 → 队列（3 并发）→ 切片还原 → PNG → PDF，落到 `Documents/JMComics/`，同名自动 `(2)` |
| 前台服务 | 下载中锁屏/切后台不中断，通知栏显示进度 |
| 收藏 | **五角星一键收藏**；**本地账本 + 服务端镜像**：断网可收藏、撤销、分文件夹、按更新时间排序；登录后对账并自愈 toggle |
| 账号 | 会话 cookie 为主，**不保存密码**；登录成功即**自动双向同步收藏**（云端拉回 + 本地补推）；冷启动一次校验，失效回本地模式 |
| 历史 | 下载记录按「全部 / 已完成 / 失败 / 已取消」筛选，可打开、重试、删除 |
| 其它 | 深浅主题、线路健康度与测速、本地搜索历史、GPL-3.0 |

---

## 截图

实机截图（Android 14，1080×2408），原图见 [`ref img/`](ref%20img/)。

| 首页 | 搜索 |
|---|---|
| ![](ref%20img/Screenshot_20261115_145850.jpg) | ![](ref%20img/Screenshot_20261115_150122.jpg) |
| **详情** | **我的** |
| ![](ref%20img/Screenshot_20261115_150147.jpg) | ![](ref%20img/Screenshot_20261115_150025.jpg) |

> 截图取自 0.2.x 实机；0.3.0 新增的**五角星收藏、点赞按钮、评论区、自动同步**见
> [`docs/INTERACTION.md`](docs/INTERACTION.md) 与 [`docs/RELEASE_NOTES_0.3.0.md`](docs/RELEASE_NOTES_0.3.0.md)。

---

## 下载安装

1. 打开仓库的 **Releases** 页，下载最新 `JMComic-0.3.0-release.apk`；
2. 允许「安装未知来源应用」后安装（APK 使用 debug keystore 签名，仅自用，不上架应用商店）；
3. 首次启动如提示通知权限，建议允许（下载进度通知需要它）。

```bash
adb install -r JMComic-0.3.0-release.apk
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

# 5) 打包
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk

# 可选：按 ABI 拆包（单包约 23 MB）
flutter build apk --release --split-per-abi
```

### Windows 构建注意事项（实测踩坑）

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
| 接口全部超时 / TLS 失败 | 换代理节点；或在「我的 → 网络 → 线路测速」里换线路 |

---

## 项目结构

```
lib/
├─ core/       主题、路由、网络（dio + cookie + 线路健康）、图片算法、图标/位图、工具
├─ data/       模型、协议源（crypto/api/catalog/probe/parser）、Hive 存储、仓储（home/album/favorites/auth/…）
└─ features/   shell（两 tab）、home、album、reader、search、mine、download（含 engine）、collect、auth
test/          单元 + widget 测试（139 通过 / 2 实网 skip）+ fixtures
tools/         probe_api.ps1 / probe_forum.ps1 / probe_hosts.ps1 / scaffold.ps1 / apply_android_config.ps1 / build_app_assets.py
Plan/          交接文档 PLAN.md、网络层修复记录 Fix Plan.md
docs/          设计文档（NETWORK_MODULE / FAVORITES / INTERACTION）、UI 草稿、审查记录
```

### 协议与实现说明

- API：移动端 JSON 接口，`token = md5(ts + salt)`，响应 `AES-256-ECB/PKCS7`（key = md5hex 的 32 个 ASCII 字节）；线路与图床地址会漂移，客户端内置种子 + 多源发现 + 健康度排序。
- 下载：与 [JmScript](https://github.com/hect0x7) 的 Kotlin 实现 1:1 对齐（切片段数算法、PNG 重编码、PDF 页尺寸上限 14400、`IS_PENDING` 写 MediaStore）。
- 收藏：`POST /favorite` 是 **toggle**，因此同步时必须核对返回的 `type`，不符就反向补发一次（防静默丢收藏）。
- 互动：点赞 `POST /like {id}`（只回 `{code,msg,status}`、不回计数）、评论列表 `GET /forum?page&aid&mode=manhua`（游客可读）、发评论 `POST /comment`（multipart `comment/aid/status/comment_id`，需登录，未登录返回 401）。
- 站点域名与字段随时可能变化，协议争议以 `tools/probe_api.ps1` / `tools/probe_forum.ps1` 的实时输出为准。

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

贡献：欢迎 PR；请保持 `flutter analyze` 0 issue、`flutter test` 全绿、UI 守卫通过。涉及协议改动请同步更新 `docs/`。

---

## 许可证

本项目以 **GNU General Public License v3.0** 发布，版权归 **Copyright (C) 2026 xzxycx** 所有。
全文见 [LICENSE](LICENSE)；你也可以在 App 内「我的 → 关于 → 开源许可」查看。

主要参考与致谢：
- [JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python)（协议字段核对）
- [jm-mobile](https://github.com/Dedicatus546/jm-mobile)（登录/收藏流程参考，GPL-3.0）
