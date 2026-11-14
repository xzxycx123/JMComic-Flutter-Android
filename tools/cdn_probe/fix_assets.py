"""收尾：修正 favicon 命名冲突、去重、重建清单与 img\\README.md 索引。"""
import os, json, hashlib
from PIL import Image

ROOT = r"D:\data\product\JMComic"
IMG = os.path.join(ROOT, "img")
FAV = os.path.join(IMG, "favicon")
MASCOT = os.path.join(IMG, "mascot")
BRAND = os.path.join(IMG, "brand")

# 1) 删掉被季节性版本互相覆盖的 favicon_*.png
for size in (16, 32, 48, 64, 128):
    p = os.path.join(FAV, f"favicon_{size}.png")
    if os.path.exists(p):
        os.remove(p)

# 2) 去掉与新年版字节完全相同的重复 wordmark
dup = os.path.join(BRAND, "wordmark_18comic_red.png")
m1 = os.path.join(BRAND, "wordmark_18comic_newyear.png")
if os.path.exists(dup) and os.path.exists(m1):
    if hashlib.md5(open(dup, "rb").read()).hexdigest() == hashlib.md5(open(m1, "rb").read()).hexdigest():
        os.remove(dup)

# 3) 用新年版方形标记统一生成 favicon PNG 档
base = os.path.join(MASCOT, "mark_newyear_512.png")
if os.path.exists(base):
    im = Image.open(base).convert("RGBA")
    for size in (16, 32, 48, 64, 128, 180):
        im.resize((size, size), Image.LANCZOS).save(os.path.join(FAV, f"favicon_{size}.png"))

# 4) 重建清单
notes = {
    "brand/wordmark_18comic_newyear.png": "横版 wordmark｜新年金币版（禁漫天堂 + 18comic）",
    "brand/wordmark_18comic_sakura.png": "横版 wordmark｜樱花版",
    "brand/wordmark_jmcomic_halloween.png": "横版 wordmark｜万圣节版",
    "brand/wordmark_jmcomic_xmas.png": "横版 wordmark｜圣诞版",
    "brand/wordmark_18comic_app.png": "横版 wordmark｜APP 落地页新年版",
    "brand/wordmark_18comic_pink_2020.png": "横版 wordmark｜2020 粉色长条版",
    "brand/wordmark_18comic_2019.png": "横版 wordmark｜2019 早期小尺寸",
    "brand/promo_app_mascot.png": "官方 APP 宣传图（吉祥物 + 手写体）",
    "favicon/favicon_18comic.ico": "站点原始 favicon（16x16，2019 归档原文件）",
    "favicon/app_icon_multi.ico": "多尺寸应用图标 ico（16/32/48/64/128/256）",
    "loading/loading_cat_480.gif": "加载动画｜黑猫回首，41 帧 480x360（站点原版，灰底）",
    "loading/loading_cat_160.gif": "加载动画｜160px 宽（App 内指示器，灰底）",
    "loading/loading_cat_96.gif": "加载动画｜96px 宽（小指示器，灰底）",
    "loading/loading_cat_480_alpha.gif": "加载动画｜480x360 透明底（抠掉灰底，推荐）",
    "loading/loading_cat_160_alpha.gif": "加载动画｜160px 宽 透明底（推荐用于 Flutter）",
    "loading/loading_cat_96_alpha.gif": "加载动画｜96px 宽 透明底",
    "loading/loading_cat_frame1.png": "加载动画首帧静态图（骨架/占位）",
    "loading/loading_cat_frame1_256.png": "加载动画首帧 256px 宽",
    "loading/loading_cat_frame1_alpha.png": "加载动画首帧静态图（透明底）",
    "ui/social_sprite.png": "社交平台图标雪碧图（14 枚）",
    "ui/qr_app.png": "官方 APP 下载二维码",
    "ui/icon_jcoin.png": "J 币币种图标 50x50",
    "ui/icon_new.png": "NEW 角标 64x64",
    "ui/icon_hot.png": "热门火焰角标 48x48",
    "ui/icon_week.png": "周榜日历角标 48x48",
    "ui/icon_day.png": "日榜日历角标 48x48",
    "ui/icon_theme.png": "主题切换图标 64x64",
    "ui/icon_bbs.png": "论坛气泡图标 32x32",
    "ui/icon_more.png": "更多（加号）图标 128x128",
    "ui/icon_rocket_280.png": "启动/发射火箭图标 280x280",
}
season = {"newyear": "新年", "sakura": "樱花", "halloween": "万圣节", "xmas": "圣诞", "pink": "粉色"}

rows = []
for dirpath, _, files in os.walk(IMG):
    for f in sorted(files):
        p = os.path.join(dirpath, f)
        rel = os.path.relpath(p, IMG).replace("\\", "/")
        if rel.lower().endswith((".md",)):
            continue
        im = Image.open(p)
        note = notes.get(rel, "")
        if not note:
            stem = os.path.splitext(f)[0]
            if rel.startswith("mascot/mark_"):
                key = stem.split("_")[1]
                size = stem.rsplit("_", 1)[1]
                note = f"方形吉祥物标记｜{season.get(key, key)}版 {size}px"
            elif rel.startswith("mascot/app_icon_512"):
                note = "应用图标 512x512（Android/iOS 主图标）"
            elif rel.startswith("favicon/favicon_"):
                note = f"favicon PNG｜{os.path.splitext(f)[0].split('_')[1]}px（由新年版方形标记缩放）"
        rows.append({
            "path": rel, "w": im.width, "h": im.height,
            "format": im.format, "frames": getattr(im, "n_frames", 1),
            "bytes": os.path.getsize(p), "note": note,
        })

rows.sort(key=lambda r: (r["path"].split("/")[0], r["path"]))
with open(os.path.join(ROOT, "docs", "cdn", "img_manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(rows, fh, ensure_ascii=False, indent=2)

# 5) 写索引 README
SRC = {
    "brand/": "`https://18comic.vip/media/logo/new_logo.png`（及其 `?v=` 历史版本，经 Wayback 归档取原图）",
    "favicon/": "`https://18comic.vip/favicon.ico`；PNG 档由 `brand` 内新年版 wordmark 的方形标记缩放",
    "loading/": "`https://18comic.vip/templates/frontend/airav/img/loading-cat.gif`",
    "mascot/": "由 `brand/` 各季节 wordmark 左侧方形头像贴片裁切，再等比缩放",
    "ui/": "`https://18comic.vip/templates/frontend/airav/img/…`（phicon / share / stray 目录）",
}

lines = [
    "# img/ — JM 品牌图标与加载动画",
    "",
    "抓取目标：**站点图标（favicon / logo）** 与 **加载时图标（loading 动画）**，只取品牌与 UI 资源，",
    "**不含任何相册、封面、正文图片**。站点主站被 Cloudflare 托管挑战拦截，资源取自 Wayback 归档的原始字节（`id_` 直取，非二次压缩）。",
    "",
    "## 目录速查",
    "",
    "| 目录 | 放什么 | 文件数 |",
    "|---|---|---|",
]
counts = {}
for r in rows:
    counts[r["path"].split("/")[0]] = counts.get(r["path"].split("/")[0], 0) + 1
table = {
    "favicon": "站点 favicon（原 ico + 多尺寸 PNG + 多尺寸 ico）",
    "brand": "横版 wordmark（新年 / 樱花 / 万圣 / 圣诞 / 2020 粉色 / 2019 旧版）+ APP 宣传图",
    "loading": "黑猫加载动画（原版 480 / 160 / 96 三档 + 首帧静态图）",
    "mascot": "方形吉祥物标记（5 季 × 256/512）+ 应用主图标 512",
    "ui": "站点 UI 角标（NEW/热门/周榜/日榜/主题/论坛/更多/J币）+ 社交雪碧图 + APP 二维码",
}
for k in ("favicon", "brand", "loading", "mascot", "ui"):
    lines.append(f"| `{k}/` | {table[k]} | {counts.get(k, 0)} |")

lines += ["", "## 文件清单", ""]
cur = None
for r in rows:
    top = r["path"].split("/")[0]
    if top != cur:
        cur = top
        lines += ["", f"### `{top}/`（来源：{SRC[top + '/']}）", "", "| 文件 | 尺寸 | 格式 | 体积 | 用途 |", "|---|---|---|---|---|"]
    frames = f" ×{r['frames']}帧" if r["frames"] > 1 else ""
    kb = r["bytes"] / 1024
    lines.append(f"| `{r['path'].split('/')[-1]}` | {r['w']}×{r['h']}{frames} | {r['format']} | {kb:.1f} KB | {r['note']} |")

lines += [
    "",
    "## 用法提示",
    "",
    "- **App 主图标**：`mascot/app_icon_512.png`（512×512，RGBA）；Android 自适应图标取 `mascot/mark_*_512.png` 做前景层。",
    "- **Flutter 启动/加载指示器**：`loading/loading_cat_96.gif`（体积小）或 `loading_cat_160.gif`；骨架屏先用 `loading_cat_frame1_256.png`。",
    "- **Web favicon**：`favicon/favicon_18comic.ico` 是站点原文件；`favicon_*.png` 是同一图案的高清 PNG 档。",
    "- **导航栏标题**：`brand/wordmark_*.png` 均为 837×263 透明底横版，可直接铺在 AppBar。",
    "- 所有 PNG 均为 RGBA 透明底，GIF 为调色板 128 色。",
    "",
    "## 复现脚本",
    "",
    "| 脚本 | 作用 |",
    "|---|---|",
    "| `tools/cdn_probe/fetch_icons.ps1` | 第一批：wordmark 各版本 + 原始 favicon（Wayback `id_` 直取） |",
    "| `tools/cdn_probe/fetch_icons2.ps1` | 第二批：加载动画、方形标记、UI 角标、社交雪碧图 |",
    "| `tools/cdn_probe/build_img.py` | 归档进 `img/`、裁方形标记、派生尺寸 |",
    "| `tools/cdn_probe/make_alpha.py` | 加载动画抠灰底，导出透明版 |",
    "| `tools/cdn_probe/verify_final.py` | 生成视觉抽查图 `docs/cdn/verify_final.png` |",
    "| `tools/cdn_probe/contact_sheet.py` / `contact_sheet2.py` | 原始资源对照图 |",
    "| `tools/cdn_probe/cdp_probe.mjs` | Chrome CDP 探针（用于验证站点 CF 拦截，主站直连不可用） |",
    "",
]
with open(os.path.join(IMG, "README.md"), "w", encoding="utf-8") as fh:
    fh.write("\n".join(lines))

print("files:", len(rows))
for c, n in counts.items():
    print(f"  {c}: {n}")
