# assets 目录说明（素材放这儿）

## 目录

| 路径 | 放什么 | 格式 |
|---|---|---|
| `assets/icons/` | **所有 UI 图标**（Dock、搜索、返回、下载、阅读器 HUD、任务卡操作……），一个功能一个文件 | `.svg`（24×24，stroke 1.75，`currentColor`） |
| `assets/illustrations/` | 空态 / 错误态 / 引导插画，尺寸 160×120 或等比 | `.svg` |
| `assets/images/` | 品牌位图：应用图标、吉祥物、品牌横幅、加载动画、站点角标、二维码、火箭 | `.png` / `.gif`，由 `tools/build_app_assets.py` 从 `img/` 派生 |
| `assets/fonts/` | 自托管字体（可选）；**不放图标字体** | `.ttf` / `.otf` |

## 硬规则（写进 PLAN §7.0，评审逐条对照）

1. **全项目不使用 emoji 作为 UI 元素**（不写放大镜、箭头、房子、笑脸之类字符）<!-- ui-rules-ignore -->，也不用 `Icons.*` Material 图标字体：图标一律自绘 SVG。
2. 图标规范：`viewBox="0 0 24 24"`、`fill="none"`、`stroke="currentColor"`、`stroke-width="1.75"`、`stroke-linecap/linejoin="round"`；视觉尺寸按 16 / 20 / 24 取用。
3. 颜色不写死在 SVG 里，靠 `currentColor` 继承；Flutter 侧用 `SvgPicture.asset(..., colorFilter: ColorFilter.mode(color, BlendMode.srcIn))`。
4. 加载态不用 GIF/位图：骨架用 `shimmer`（`ShaderMask` + `AnimationController`）绘制，转圈用 `CircularProgressIndicator`，二者都不需要图片素材。
5. 新增图标必须同时更新 `lib/core/icons/app_icons.dart` 的常量表 + 本文件的清单表。

## 现有图标清单

| 文件名 | 用途 | 出现位置 |
|---|---|---|
| `home.svg` | 首页 | Dock |
| `user.svg` | 我的 / 未登录头像位 | Dock、我的页资料卡 |
| `download.svg` | 下载 tab、下载 CTA | Dock、详情页 |
| `search.svg` | 搜索入口、搜索页输入框前缀 | 首页 AppBar、搜索页 |
| `back.svg` / `forward.svg` | 返回 / 前进、列表「更多」 | 各页 AppBar |
| `close.svg` | 关闭（阅读器退出、弹窗） | 阅读器 HUD、对话框 |
| `theme.svg` | 主题切换 | 首页 AppBar、设置页 |
| `bookmark.svg` | 收藏 | 详情页、我的页 |
| `play.svg` | 开始阅读 / 继续阅读 | 详情页主按钮 |
| `book-open.svg` | 阅读器模式、章节列表 | 阅读器 HUD、详情页 |
| `grid.svg` / `list.svg` | 视图切换（瀑布流 / 列表） | 搜索结果、分类页 |
| `refresh.svg` | 重新探测线路 / 重试 | 我的页、错误态 |
| `pause.svg` | 暂停下载 | 任务卡 |
| `trash.svg` | 删除记录 | 任务卡 |
| `folder.svg` | 下载目录 | 我的页 |
| `share.svg` | 分享 / 打开 | 任务卡、详情页 |
| `settings.svg` | 设置（滑杆造型） | 我的页 |
| `check.svg` / `alert.svg` | 成功 / 失败状态 | 任务卡状态、提示 |
| `scroll-mode.svg` | 阅读器：上下滚动模式 | 阅读器 HUD 切换 |
| `page-mode.svg` | 阅读器：左右翻页模式 | 阅读器 HUD 切换 |

## 插画清单

| 文件名 | 用途 |
|---|---|
| `empty-search.svg` | 搜索无结果 |
| `empty-download.svg` | 下载列表为空（现由火箭位图接管，保留兜底） |
| `error-network.svg` | 网络/线路错误态 |

## 品牌位图清单（`assets/images/`，入口：`lib/core/icons/app_images.dart`）

| 文件名 | 来源（`img/`） | 用途 / 出现位置 |
|---|---|---|
| `app_icon.png` (512²) | `mascot/app_icon_512.png` | 关于页图标；Android 桌面图标由脚本派生到 `mipmap-*/ic_launcher.png`；启动屏居中位图 |
| `mark_default.png` | `mascot/app_icon_512.png` | 方形吉祥物兜底 |
| `mark_newyear.png` / `mark_halloween.png` / `mark_xmas.png` / `mark_sakura.png` / `mark_pink.png` | `mascot/mark_*_256.png` | 首页 AppBar 左侧、我的页头像：按月份自动切换（1 月新年 / 3–4 月樱花 / 10 月万圣 / 12 月圣诞） |
| `brand_banner.png` (1000×400) | `brand/brand.png`（容器是 PNG、内容是 WebP，脚本转真 PNG） | 关于页顶部品牌横幅 |
| `loading_cat.gif` (96×72) | `loading/loading_cat_96_alpha.gif` | 紧凑内联加载（阅读器 HUD 附近） |
| `loading_cat_large.gif` (160×120) | `loading/loading_cat_160_alpha.gif` | 详情页 / 章节加载中的黑猫动图 |
| `loading_cat_frame.png` | `loading/loading_cat_frame1_alpha.png` | 动图解码失败时的静态兜底 |
| `qr_app.png` (400²) | `ui/qr_app.png` | 关于页官方 APP 二维码卡片 |
| `badge_new.png` | `ui/icon_new.png` | 列表卡片右上角 NEW 角标（`adddate` 7 天内） |
| `badge_hot.png` / `badge_day.png` / `badge_week.png` | `ui/icon_hot|day|week.png` | 首页排序条（人气推荐 / 日榜 / 周榜） |
| `rocket.png` (280²) | `ui/icon_rocket_280.png` | 下载页空态主图 |

> 图标位规则不变：**交互图标一律 `assets/icons/*.svg`**；位图只做品牌、装饰、空态主图与加载动画。
> 新增位图必须同步 `lib/core/icons/app_images.dart` + 本表，并跑 `python tools/build_app_assets.py` 重新派生。
