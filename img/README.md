# img/ — JM 品牌图标与加载动画

抓取目标：**站点图标（favicon / logo）** 与 **加载时图标（loading 动画）**，只取品牌与 UI 资源，
**不含任何相册、封面、正文图片**。站点主站被 Cloudflare 托管挑战拦截，资源取自 Wayback 归档的原始字节（`id_` 直取，非二次压缩）。

## 目录速查

| 目录 | 放什么 | 文件数 |
|---|---|---|
| `favicon/` | 站点 favicon（原 ico + 多尺寸 PNG + 多尺寸 ico） | 8 |
| `brand/` | 横版 wordmark（新年 / 樱花 / 万圣 / 圣诞 / 2020 粉色 / 2019 旧版）+ APP 宣传图 | 8 |
| `loading/` | 黑猫加载动画（原版 480 / 160 / 96 三档 + 首帧静态图） | 9 |
| `mascot/` | 方形吉祥物标记（5 季 × 256/512）+ 应用主图标 512 | 11 |
| `ui/` | 站点 UI 角标（NEW/热门/周榜/日榜/主题/论坛/更多/J币）+ 社交雪碧图 + APP 二维码 | 11 |

## 文件清单


### `brand/`（来源：`https://18comic.vip/media/logo/new_logo.png`（及其 `?v=` 历史版本，经 Wayback 归档取原图））

| 文件 | 尺寸 | 格式 | 体积 | 用途 |
|---|---|---|---|---|
| `promo_app_mascot.png` | 816×575 | PNG | 252.3 KB | 官方 APP 宣传图（吉祥物 + 手写体） |
| `wordmark_18comic_2019.png` | 200×63 | PNG | 22.5 KB | 横版 wordmark｜2019 早期小尺寸 |
| `wordmark_18comic_app.png` | 837×263 | PNG | 159.8 KB | 横版 wordmark｜APP 落地页新年版 |
| `wordmark_18comic_newyear.png` | 837×263 | PNG | 292.9 KB | 横版 wordmark｜新年金币版（禁漫天堂 + 18comic） |
| `wordmark_18comic_pink_2020.png` | 837×263 | PNG | 154.3 KB | 横版 wordmark｜2020 粉色长条版 |
| `wordmark_18comic_sakura.png` | 837×263 | PNG | 151.7 KB | 横版 wordmark｜樱花版 |
| `wordmark_jmcomic_halloween.png` | 837×263 | PNG | 153.3 KB | 横版 wordmark｜万圣节版 |
| `wordmark_jmcomic_xmas.png` | 837×263 | PNG | 176.5 KB | 横版 wordmark｜圣诞版 |

### `favicon/`（来源：`https://18comic.vip/favicon.ico`；PNG 档由 `brand` 内新年版 wordmark 的方形标记缩放）

| 文件 | 尺寸 | 格式 | 体积 | 用途 |
|---|---|---|---|---|
| `app_icon_multi.ico` | 256×256 | ICO | 179.6 KB | 多尺寸应用图标 ico（16/32/48/64/128/256） |
| `favicon_128.png` | 128×128 | PNG | 37.2 KB | favicon PNG｜128px（由新年版方形标记缩放） |
| `favicon_16.png` | 16×16 | PNG | 0.9 KB | favicon PNG｜16px（由新年版方形标记缩放） |
| `favicon_180.png` | 180×180 | PNG | 67.5 KB | favicon PNG｜180px（由新年版方形标记缩放） |
| `favicon_18comic.ico` | 16×16 | ICO | 1.1 KB | 站点原始 favicon（16x16，2019 归档原文件） |
| `favicon_32.png` | 32×32 | PNG | 3.1 KB | favicon PNG｜32px（由新年版方形标记缩放） |
| `favicon_48.png` | 48×48 | PNG | 6.5 KB | favicon PNG｜48px（由新年版方形标记缩放） |
| `favicon_64.png` | 64×64 | PNG | 10.9 KB | favicon PNG｜64px（由新年版方形标记缩放） |

### `loading/`（来源：`https://18comic.vip/templates/frontend/airav/img/loading-cat.gif`）

| 文件 | 尺寸 | 格式 | 体积 | 用途 |
|---|---|---|---|---|
| `loading_cat_160.gif` | 160×120 ×41帧 | GIF | 131.6 KB | 加载动画｜160px 宽（App 内指示器，灰底） |
| `loading_cat_160_alpha.gif` | 160×120 ×41帧 | GIF | 96.4 KB | 加载动画｜160px 宽 透明底（推荐用于 Flutter） |
| `loading_cat_480.gif` | 480×360 ×41帧 | GIF | 554.8 KB | 加载动画｜黑猫回首，41 帧 480x360（站点原版，灰底） |
| `loading_cat_480_alpha.gif` | 480×360 ×41帧 | GIF | 502.6 KB | 加载动画｜480x360 透明底（抠掉灰底，推荐） |
| `loading_cat_96.gif` | 96×72 ×41帧 | GIF | 67.4 KB | 加载动画｜96px 宽（小指示器，灰底） |
| `loading_cat_96_alpha.gif` | 96×72 ×41帧 | GIF | 48.6 KB | 加载动画｜96px 宽 透明底 |
| `loading_cat_frame1.png` | 480×360 | PNG | 53.1 KB | 加载动画首帧静态图（骨架/占位） |
| `loading_cat_frame1_256.png` | 256×192 | PNG | 21.9 KB | 加载动画首帧 256px 宽 |
| `loading_cat_frame1_alpha.png` | 480×360 | PNG | 45.4 KB | 加载动画首帧静态图（透明底） |

### `mascot/`（来源：由 `brand/` 各季节 wordmark 左侧方形头像贴片裁切，再等比缩放）

| 文件 | 尺寸 | 格式 | 体积 | 用途 |
|---|---|---|---|---|
| `app_icon_512.png` | 512×512 | PNG | 382.6 KB | 应用图标 512x512（Android/iOS 主图标） |
| `mark_halloween_256.png` | 256×256 | PNG | 99.8 KB | 方形吉祥物标记｜万圣节版 256px |
| `mark_halloween_512.png` | 512×512 | PNG | 296.9 KB | 方形吉祥物标记｜万圣节版 512px |
| `mark_newyear_256.png` | 256×256 | PNG | 120.7 KB | 方形吉祥物标记｜新年版 256px |
| `mark_newyear_512.png` | 512×512 | PNG | 371.6 KB | 方形吉祥物标记｜新年版 512px |
| `mark_pink_256.png` | 256×256 | PNG | 113.0 KB | 方形吉祥物标记｜粉色版 256px |
| `mark_pink_512.png` | 512×512 | PNG | 341.2 KB | 方形吉祥物标记｜粉色版 512px |
| `mark_sakura_256.png` | 256×256 | PNG | 112.3 KB | 方形吉祥物标记｜樱花版 256px |
| `mark_sakura_512.png` | 512×512 | PNG | 346.9 KB | 方形吉祥物标记｜樱花版 512px |
| `mark_xmas_256.png` | 256×256 | PNG | 117.9 KB | 方形吉祥物标记｜圣诞版 256px |
| `mark_xmas_512.png` | 512×512 | PNG | 365.2 KB | 方形吉祥物标记｜圣诞版 512px |

### `ui/`（来源：`https://18comic.vip/templates/frontend/airav/img/…`（phicon / share / stray 目录））

| 文件 | 尺寸 | 格式 | 体积 | 用途 |
|---|---|---|---|---|
| `icon_bbs.png` | 32×32 | PNG | 2.7 KB | 论坛气泡图标 32x32 |
| `icon_day.png` | 48×48 | PNG | 1.1 KB | 日榜日历角标 48x48 |
| `icon_hot.png` | 48×48 | PNG | 1.5 KB | 热门火焰角标 48x48 |
| `icon_jcoin.png` | 50×50 | PNG | 1.2 KB | J 币币种图标 50x50 |
| `icon_more.png` | 128×128 | PNG | 3.0 KB | 更多（加号）图标 128x128 |
| `icon_new.png` | 64×64 | PNG | 4.5 KB | NEW 角标 64x64 |
| `icon_rocket_280.png` | 280×280 | PNG | 19.3 KB | 启动/发射火箭图标 280x280 |
| `icon_theme.png` | 64×64 | PNG | 1.4 KB | 主题切换图标 64x64 |
| `icon_week.png` | 48×48 | PNG | 0.9 KB | 周榜日历角标 48x48 |
| `qr_app.png` | 400×400 | PNG | 27.8 KB | 官方 APP 下载二维码 |
| `social_sprite.png` | 374×26 | PNG | 33.5 KB | 社交平台图标雪碧图（14 枚） |

## 用法提示

- **App 主图标**：`mascot/app_icon_512.png`（512×512，RGBA）；Android 自适应图标取 `mascot/mark_*_512.png` 做前景层。
- **Flutter 启动/加载指示器**：优先用透明底档 —— `loading/loading_cat_96_alpha.gif`（48.6 KB，体积最小）或 `loading_cat_160_alpha.gif`；需要静态占位时用 `loading_cat_frame1_alpha.png`。灰底 `*.gif` 是站点原版，留档对照用。
- **启动图（splash）**：`brand/promo_app_mascot.png` 或 `loading/loading_cat_480.gif` 放大铺底均可。
- **Web favicon**：`favicon/favicon_18comic.ico` 是站点原文件；`favicon_*.png` 是同一图案的高清 PNG 档。
- **导航栏标题**：`brand/wordmark_*.png` 均为 837×263 透明底横版，可直接铺在 AppBar。
- 所有 PNG 均为 RGBA 透明底，GIF 为调色板 128 色。

## 复现脚本

| 脚本 | 作用 |
|---|---|
| `tools/cdn_probe/fetch_icons.ps1` | 第一批：wordmark 各版本 + 原始 favicon（Wayback `id_` 直取） |
| `tools/cdn_probe/fetch_icons2.ps1` | 第二批：加载动画、方形标记、UI 角标、社交雪碧图 |
| `tools/cdn_probe/build_img.py` | 归档进 `img/`、裁方形标记、派生尺寸 |
| `tools/cdn_probe/make_alpha.py` | 加载动画抠灰底，导出透明版 |
| `tools/cdn_probe/verify_final.py` | 生成视觉抽查图 `docs/cdn/verify_final.png` |
| `tools/cdn_probe/contact_sheet.py` / `contact_sheet2.py` | 原始资源对照图 |
| `tools/cdn_probe/cdp_probe.mjs` | Chrome CDP 探针（用于验证站点 CF 拦截，主站直连不可用） |
