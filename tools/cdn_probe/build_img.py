"""把抓到的 JM 品牌资源整理进 img\\：分类归档 + 派生图标尺寸。
仅处理品牌/UI 资源，不涉及任何相册内容。
"""
import os, json, shutil
from PIL import Image

ROOT = r"D:\data\product\JMComic"
RAW = os.path.join(ROOT, "img", "_raw")
IMG = os.path.join(ROOT, "img")

DIRS = {
    "favicon": os.path.join(IMG, "favicon"),
    "brand": os.path.join(IMG, "brand"),
    "loading": os.path.join(IMG, "loading"),
    "mascot": os.path.join(IMG, "mascot"),
    "ui": os.path.join(IMG, "ui"),
}
for d in DIRS.values():
    os.makedirs(d, exist_ok=True)

manifest = []


def rec(path, note, src):
    im = Image.open(path)
    manifest.append({
        "path": os.path.relpath(path, IMG).replace("\\", "/"),
        "size": f"{im.width}x{im.height}",
        "format": im.format,
        "frames": getattr(im, "n_frames", 1),
        "bytes": os.path.getsize(path),
        "note": note,
        "src": src,
    })


# ---------- 1. 原始归档拷贝 ----------
COPY = [
    ("brand", "wordmark_18comic_newyear.png",   "logo_18comic_2021_hi.png",  "新年金币版横版 wordmark（禁漫天堂 + 18comic）"),
    ("brand", "wordmark_18comic_red.png",       "logo_18comic_2023_30208.png","同款高清横版 wordmark（备用同源副本）"),
    ("brand", "wordmark_18comic_sakura.png",    "logo_18comic_2023_30521.png","樱花版横版 wordmark"),
    ("brand", "wordmark_jmcomic_halloween.png", "logo_jmcomic_2022.png",      "万圣节版横版 wordmark"),
    ("brand", "wordmark_jmcomic_xmas.png",      "logo_jmcomic_2023_0928.png", "圣诞版横版 wordmark"),
    ("brand", "wordmark_18comic_app.png",       "logo_square_stray.png",      "新年版横版 wordmark（app 落地页用）"),
    ("brand", "wordmark_18comic_2019.png",      "logo_2019_small.png",        "2019 早期小尺寸 wordmark（200x63）"),
    ("brand", "wordmark_18comic_pink_2020.png", "logo_new2_2020.png",         "2020 粉色长条 wordmark"),
    ("brand", "promo_app_mascot.png",           "logo_stray_title.png",       "官方 APP 宣传图（吉祥物 + 手写体）"),
    ("loading", "loading_cat_480.gif",          "loading_cat.gif",            "站点加载动画：黑猫回首（41 帧 / 原版）"),
    ("ui", "social_sprite.png",                 "sprite_social_media.png",    "社交平台图标雪碧图（微博/贴吧/推特/Discord 等 14 枚）"),
    ("ui", "icon_jcoin.png",                    "icon_jcoin.png",             "J 币币种图标 50x50"),
    ("ui", "icon_new.png",                      "icon_new.png",               "NEW 角标 64x64"),
    ("ui", "icon_hot.png",                      "icon_hot.png",               "热门火焰角标 48x48"),
    ("ui", "icon_week.png",                     "icon_week.png",              "周榜日历角标 48x48"),
    ("ui", "icon_day.png",                      "icon_day.png",               "日榜日历角标 48x48"),
    ("ui", "icon_theme.png",                    "icon_theme.png",             "主题切换图标 64x64"),
    ("ui", "icon_bbs.png",                      "icon_bbs.png",               "论坛气泡图标 32x32"),
    ("ui", "icon_more.png",                     "icon_more.png",              "更多（加号）图标 128x128"),
    ("ui", "icon_rocket_280.png",               "icon_potato_big.png",        "启动/发射火箭图标 280x280（原 phicon/potato.png）"),
]
for sub, name, raw_name, note in COPY:
    src = os.path.join(RAW, raw_name)
    if not os.path.exists(src):
        print("MISSING", raw_name)
        continue
    dst = os.path.join(DIRS[sub], name)
    shutil.copyfile(src, dst)
    rec(dst, note, raw_name)

# ---------- 2. favicon ----------
ico_src = os.path.join(RAW, "favicon_18comic_2019.ico")
ico_dst = os.path.join(DIRS["favicon"], "favicon_18comic.ico")
shutil.copyfile(ico_src, ico_dst)
rec(ico_dst, "站点原始 favicon（16x16，2019 版）", "favicon_18comic_2019.ico")

# ---------- 3. 从横版 wordmark 裁方形吉祥物标记 ----------
SOURCES = [
    ("wordmark_18comic_newyear.png", "mark_newyear"),
    ("wordmark_18comic_sakura.png", "mark_sakura"),
    ("wordmark_jmcomic_halloween.png", "mark_halloween"),
    ("wordmark_jmcomic_xmas.png", "mark_xmas"),
    ("wordmark_18comic_pink_2020.png", "mark_pink"),
]
marks = {}
for fname, stem in SOURCES:
    p = os.path.join(DIRS["brand"], fname)
    if not os.path.exists(p):
        continue
    im = Image.open(p).convert("RGBA")
    h = im.height
    # 方形头像贴片位于左侧，正方形边长≈图像高度
    box = (0, 0, min(h, im.width), h)
    tile = im.crop(box)
    # 去掉贴片外的透明/白边
    bbox = tile.getchannel("A").getbbox()
    if bbox:
        tile = tile.crop(bbox)
    side = min(tile.size)
    left = (tile.width - side) // 2
    top = (tile.height - side) // 2
    tile = tile.crop((left, top, left + side, top + side))
    marks[stem] = tile
    for size in (256, 512):
        out = tile.resize((size, size), Image.LANCZOS)
        op = os.path.join(DIRS["mascot"], f"{stem}_{size}.png")
        out.save(op)
        rec(op, f"方形吉祥物标记 {size}px（由 {fname} 裁切）", fname)
    # 同时导出 favicon 尺寸
    for size in (16, 32, 48, 64, 128):
        out = tile.resize((size, size), Image.LANCZOS)
        op = os.path.join(DIRS["favicon"], f"favicon_{size}.png")
        out.save(op)
        rec(op, f"favicon {size}px（由新年版方形标记缩放）" if stem == "mark_newyear" else f"{stem} {size}px",
            fname)

# 多尺寸 ico（含 16~256），便于 Windows/Flutter 桌面使用
if "mark_newyear" in marks:
    big = marks["mark_newyear"].resize((256, 256), Image.LANCZOS)
    ico_out = os.path.join(DIRS["favicon"], "app_icon_multi.ico")
    big.save(ico_out, sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    rec(ico_out, "多尺寸应用图标 ico（16/32/48/64/128/256）", "裁切自 wordmark")

    app512 = os.path.join(DIRS["mascot"], "app_icon_512.png")
    big.resize((512, 512), Image.LANCZOS).save(app512)
    rec(app512, "应用图标 512x512（Android/iOS 主图标可直接用）", "裁切自 wordmark")

# ---------- 4. 加载动画：尺寸档 + 静态首帧 ----------
gif_src = os.path.join(DIRS["loading"], "loading_cat_480.gif")
if os.path.exists(gif_src):
    src = Image.open(gif_src)
    frames = []
    durations = []
    for i in range(src.n_frames):
        src.seek(i)
        frames.append(src.convert("RGBA"))
        durations.append(src.info.get("duration", 70))

    def save_gif(target_w, name, note):
        ratio = target_w / frames[0].width
        size = (target_w, max(1, int(frames[0].height * ratio)))
        scaled = [f.resize(size, Image.LANCZOS) for f in frames]
        # 量化到调色板，控制体积
        pal = [f.convert("RGB").quantize(colors=128, method=Image.MEDIANCUT) for f in scaled]
        out = os.path.join(DIRS["loading"], name)
        pal[0].save(out, save_all=True, append_images=pal[1:], duration=durations,
                    loop=0, optimize=True, disposal=2)
        rec(out, note, "loading_cat_480.gif")

    save_gif(160, "loading_cat_160.gif", "加载动画 160px 宽（App 内指示器，41 帧）")
    save_gif(96, "loading_cat_96.gif", "加载动画 96px 宽（小尺寸指示器）")

    first = frames[0]
    op = os.path.join(DIRS["loading"], "loading_cat_frame1.png")
    first.save(op)
    rec(op, "加载动画首帧静态图（骨架/占位用）", "loading_cat_480.gif")
    op2 = os.path.join(DIRS["loading"], "loading_cat_frame1_256.png")
    first.resize((256, int(first.height * 256 / first.width)), Image.LANCZOS).save(op2)
    rec(op2, "加载动画首帧 256px 宽", "loading_cat_480.gif")

# ---------- 5. 清理中间件 ----------
keep = os.path.join(IMG, "_raw")
if os.path.isdir(keep):
    for f in os.listdir(keep):
        os.remove(os.path.join(keep, f))
    os.rmdir(keep)
kp = os.path.join(IMG, ".keep")
if os.path.exists(kp):
    os.remove(kp)

with open(os.path.join(ROOT, "docs", "cdn", "img_manifest.json"), "w", encoding="utf-8") as fh:
    json.dump(manifest, fh, ensure_ascii=False, indent=2)

print(f"整理完成，共 {len(manifest)} 个文件")
for m in manifest:
    print(f"  {m['path']:42s} {m['size']:>10s} {m['format']:<4s} {m['bytes']:>7d}B  {m['note']}")
