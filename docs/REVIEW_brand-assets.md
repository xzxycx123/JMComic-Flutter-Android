# 品牌图片素材接入 · 审查记录

- 审查对象：`img/` → `assets/images/` → App 各处（品牌、加载、角标、二维码、启动图标/启动屏）
- 审查时间：2026-11-15
- 审查方式：**自审**。本会话被限制为委派子代理（delegation depth 1/1，剩余层级 0），无法再 `subagent`，
  因此按下面的等价清单逐项人工过一遍 + 用脚本/命令取证，替代独立子代理复核。

## 一、素材映射（谁进了包、用在哪）

| 源文件（`img/`） | 产物（`assets/images/`） | 使用位置 |
|---|---|---|
| `mascot/app_icon_512.png` | `app_icon.png` (512²) | 关于页 BrandMark、Android 启动器图标、启动屏 |
| `mascot/mark_*.png` | `mark_default/newyear/sakura/halloween/xmas.png` (256²) | `BrandMark`（首页 AppBar 26px、我的页头像 56px、关于页 56px）；按月份自动换季 |
| `brand/brand.png` | `brand_banner.png` (1000×400，WebP 转真 PNG) | 关于页顶部品牌横幅 |
| `loading/loading_cat_96_alpha.gif` | `loading_cat.gif` (96×72，41 帧) | `MascotLoading(compact:)` 内联加载 |
| `loading/loading_cat_160_alpha.gif` | `loading_cat_large.gif` (160×120，41 帧) | `MascotLoading` 首屏/详情加载、阅读器 |
| `loading/loading_cat_frame1_alpha.png` | `loading_cat_frame.png` | 关闭动效 / 解码失败时的静态兜底 |
| `ui/qr_app.png` | `qr_app.png` (400²) | 关于页「官方 App」二维码卡片 |
| `ui/icon_rocket_280.png` | `rocket.png` | 下载空态主图 |
| `ui/icon_new.png` | `badge_new.png` | 封面右上「NEW」角标（`isNew` 判定：上架 ≤ 7 天） |
| `ui/icon_day|week|hot.png` | `badge_day/week/hot.png` | 首页排序条 `SortChips` 的日榜/周榜/热门 |
| `mascot/app_icon_512.png` | `android/…/mipmap-*/ic_launcher.png` | 启动器图标 48/72/96/144/192 |
| `mascot/app_icon_512.png` | `@mipmap/ic_launcher`（`launch_background.xml`） | Android 启动屏居中图标 |

派生脚本：`tools/build_app_assets.py`（幂等，`--dry-run` 可预览）。

## 二、逐项检查结果

| 检查项 | 方法 | 结果 |
|---|---|---|
| 引用完整性 | 扫 `lib/**/*.dart` 里 `assets/...` 字符串，逐个查文件存在 | ✅ 42 处引用，0 缺失 |
| 资源冗余 | 反查 `assets/images/*` 是否被引用 | ⚠️ `mark_pink.png` 未引用（见 P2-3） |
| 图片格式/尺寸 | Pillow 逐张打开 | ✅ 全部 PNG/GIF 正常；GIF 41 帧、透明底；`brand_banner` 已是真 PNG（非 WebP 容器） |
| 体积 | 统计 `assets/` 总量 | ✅ 1.6 MB（PNG/GIF 已按需降采样） |
| 静态检查 | `flutter analyze` | ✅ No issues found |
| 测试 | `flutter test` | ✅ 75 用例全绿（含 `test/features/assets_test.dart`） |
| UI 规则 | `tools\check_ui_rules.ps1` | ✅ 无 emoji、无 `Icons.*`、`assets/icons` 全 SVG |
| 语义 | 读代码 | ✅ `BrandMark` / `MascotLoading` / `BrandBanner` / 角标都带 `semanticLabel` |
| 动效降级 | 读代码 | ✅ GIF 失败回落 `loading_cat_frame.png`；`gaplessPlayback: true`（无闪帧） |
| 深色主题 | 读代码 + 走查 | ⚠️ About 横幅是白底图，深色下呈白色卡片（见 P2-2），可接受 |
| 启动器图标 | 查 `android/…/mipmap-*` | ✅ 已替换为品牌图标（5 个密度）；⚠️ 无 adaptive icon（见 P2-4） |
| 启动屏 | 查 `launch_background.xml` | ✅ 白底 + 居中 `@mipmap/ic_launcher` |
| APK 打包 | `unzip -l app-release.apk | findstr assets/images` | 见 §四（构建后回填） |

## 三、发现的问题（按优先级）

**P0 / P1：无。** 没有会导致编译失败、崩溃、素材缺失或规则违规的问题。

**P2（打磨项，可后续处理）**

1. **排序条把 PNG 角标当 14px 图标用**（`sort_chips.dart`）。PLAN §7.0 的原则是「UI 图标一律 SVG」；
   这里用的是 `assets/images/*.png`，不在守卫脚本的 `assets/icons` 规则内，所以不被拦。
   判为「品牌角标」可接受，但若严格守规，建议后续用 `assets/icons/day.svg|week.svg|hot.svg` 取代。
2. **关于页横幅的白色底**：`brand_banner.png` 原图白底，深色主题下是一块白色卡片。
   当前外层有 `ColoredBox(surfaceContainer)`，视觉上像「品牌卡片」；如需更贴合深色，
   建议补 1px `outline` 描边（保持白底不变）。
3. **`mark_pink.png` 未引用**：会随包打进 APK 但永远不显示（≈114 KB）。`AppImages.seasonalMark()`
   只映射 1/3-4/10/12 月，粉色版没有季节语义。处理方式二选一：从 `build_app_assets.py` 的产物里删掉，
   或给 5 月加一条粉色映射。
4. **缺 Android 自适应图标**：只有 legacy `mipmap-*/ic_launcher.png`。Android 8+ 启动器会把
   方形图放大裁切（猫耳可能被切）。建议补 `mipmap-anydpi-v26/ic_launcher.xml`
   （background = 品牌橙，foreground = 缩放后的吉祥物）。

另核过一个可疑点：`loading_cat.gif` 与 `loading_cat_large.gif` 字节数都恰好是 98,682 B。
已用 Pillow + SHA256 交叉验证：尺寸/帧数不同、哈希不同，不是复制错误，只是巧合。

## 四、构建与打包验证（本轮实跑）

```powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-17.0.4'   # 64 位 JDK；默认 java 是 32 位 Liberica
$env:Path = 'D:\data\tools\flutter\bin;' + $env:Path
flutter build apk --release
```

| 项 | 实测值 |
|---|---|
| 产物 | `build\app\outputs\flutter-apk\app-release.apk`（同时 `apk\release\` 一份） |
| 体积 | 65,661,173 B ≈ **62.62 MB**（universal，含 3 个 ABI） |
| ABI | `arm64-v8a` / `armeabi-v7a` / `x86_64`（各有 `libapp.so`） |
| 归档 | `dist\JMComic-0.1.0-release.apk`，与本次构建 **byte 一致** |
| SHA256 | `E2B2D8CA2EDF27711EC81D441E090D288FC8A823FC5315DF20602848F9943F6B` |
| 包信息 | `com.jmcomic.jm_comic`，versionCode 1 / versionName 0.1.0 |
| SDK | minSdk 29 · targetSdk 35 · compileSdk 36（AGP 9 / 插件下限） |
| 展示名 / 图标 | `application-label: JMComic`、`application-icon` 5 档密度（品牌图标，非默认 Flutter 图标） |
| 权限 | INTERNET / ACCESS_NETWORK_STATE / POST_NOTIFICATIONS / FOREGROUND_SERVICE(_DATA_SYNC) / WAKE_LOCK + 插件自带（BOOT_COMPLETED、媒体读取） |
| 服务 | `com.pravera.flutter_foreground_task.service.ForegroundService`（`foregroundServiceType=dataSync`）已注册 |
| 图片素材 | `assets/flutter_assets/assets/images/` 下 **17 个**文件全部进包（≈1.7 MB，含 2 个 GIF） |
| 签名 | 模板默认 **debug keystore**（可直接安装自测；上架需换 `signingConfig`） |

构建期的环境坑（与代码无关，已在 `docs/IMPLEMENTATION.md` 记录）：JDK 必须是 64 位、
Gradle 需走代理、`platforms;android-34`（`flutter_foreground_task` 的 compileSdk）要装、
Kotlin 跨盘符需 `kotlin.incremental=false`、残留 Gradle daemon 会锁文件（`gradlew --stop` 后重试）。
本轮 3 次尝试中 2 次是环境性失败（native lib 文件被占、`app.dill` 缺失），`flutter clean` + 停 daemon 后一次通过。

## 五、结论

图片素材已按「品牌位图只做品牌表达、图标仍走 SVG」的边界接入：启动器图标与启动屏、
首页 / 我的 / 关于的品牌标识、加载动图、下载空态主图、NEW 角标、榜单角标、官方二维码全部就位；
`analyze` / `test` / UI 守卫三绿，`flutter build apk --release` 通过并归档到 `dist/`。
P2 四项属打磨，不影响本轮交付。

---

## 六、后续变更（2026-11-15 同日，审查修复后）

1. **素材降采样**（体积 1.6 MB → 0.54 MB）：`mark_*` 256² → 96²、`app_icon` 512² → 128²、`brand_banner` 1000×400 → 640×256、`loading_cat_frame` 480×360 → 160×120、`qr_app` 400² → 192²、`rocket` 280² → 192²、`badge_*` 48²。
2. **`mark_pink.png` 不再冗余**：`AppImages.seasonalMark()` 增加了 5 月 → 粉色版映射。
3. **启动屏不再直接引用 mipmap**：新增 `res/drawable-nodpi/splash_logo.png`（256²，由脚本派生），`launch_background.xml` / `drawable-v21` 改引用它；新增 `res/values-v31/styles.xml` 配 `windowSplashScreenBackground` + `windowSplashScreenAnimatedIcon`，避免 Android 12+ 二次闪屏、也为将来自适应图标留路。
4. **排序条角标可读性**：`badge_day/week/hot` 外套 18² 圆底（`surfaceContainerHigh`），浅色主题下不再与白底糊在一起。
5. **网格比例**：`home` / `search` / `album related` 三处统一 `childAspectRatio: 0.52`（320dp + 1.3 字体不再溢出）。
6. **空态自适应**：`EmptyState` 加滚动 + 小高度紧凑模式，下载页键盘弹起时不再 RenderFlex 溢出。
7. **阅读器加载卡**：白底卡片改为 `darkSurfaceContainer` + 描边，深色底不再闪白。
8. **重新打包**：`dist\JMComic-0.1.0-release.apk` 61.76 MB，SHA256 `3CB6FB84…C23E3DF`；`flutter test` 78 用例全绿。
