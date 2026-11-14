"""最终校验图：img/ 内关键资源的视觉抽查（不含原始 wordmark 重复项）。"""
import os
from PIL import Image, ImageDraw

IMG = r"D:\data\product\JMComic\img"
OUT = r"D:\data\product\JMComic\docs\cdn\verify_final.png"

items = [
    ("mascot/app_icon_512.png", 200),
    ("mascot/mark_newyear_256.png", 120),
    ("mascot/mark_sakura_256.png", 120),
    ("mascot/mark_halloween_256.png", 120),
    ("mascot/mark_xmas_256.png", 120),
    ("mascot/mark_pink_256.png", 120),
    ("favicon/favicon_128.png", 96),
    ("favicon/favicon_48.png", 48),
    ("favicon/favicon_16.png", 16),
    ("ui/qr_app.png", 140),
    ("ui/icon_jcoin.png", 50),
    ("ui/icon_new.png", 64),
    ("ui/icon_hot.png", 48),
    ("ui/icon_theme.png", 64),
    ("ui/icon_rocket_280.png", 140),
    ("ui/social_sprite.png", 374),
    ("brand/wordmark_18comic_newyear.png", 380),
    ("brand/wordmark_18comic_sakura.png", 380),
    ("brand/wordmark_jmcomic_halloween.png", 380),
    ("brand/wordmark_jmcomic_xmas.png", 380),
    ("brand/promo_app_mascot.png", 380),
    ("loading/loading_cat_frame1.png", 240),
]

W = 820
rows = []
for path, target_w in items:
    p = os.path.join(IMG, path)
    if not os.path.exists(p):
        continue
    im = Image.open(p)
    if getattr(im, "n_frames", 1) > 1:
        im.seek(0)
    im = im.convert("RGBA")
    if im.width > target_w:
        h = int(im.height * target_w / im.width)
        im = im.resize((target_w, h), Image.LANCZOS)
    rows.append((path, im))

# 加载动画帧拼条
gif = os.path.join(IMG, "loading/loading_cat_160.gif")
strip = None
if os.path.exists(gif):
    g = Image.open(gif)
    picks = [0, 10, 20, 30, 40]
    frames = []
    for idx in picks:
        if idx < g.n_frames:
            g.seek(idx)
            frames.append(g.convert("RGBA"))
    if frames:
        strip = Image.new("RGBA", (sum(f.width for f in frames), max(f.height for f in frames)), (255, 255, 255, 255))
        x = 0
        for f in frames:
            strip.alpha_composite(f, (x, 0))
            x += f.width

height_total = 20 + sum(im.height + 26 for _, im in rows) + (strip.height + 26 if strip else 0)
canvas = Image.new("RGBA", (W, height_total), (248, 248, 250, 255))
d = ImageDraw.Draw(canvas)
y = 10
for path, im in rows:
    d.text((10, y), path, fill=(20, 20, 20, 255))
    y += 16
    canvas.alpha_composite(im, (10, y))
    y += im.height + 10
if strip:
    d.text((10, y), "loading/loading_cat_160.gif  (帧 0/10/20/30/40)", fill=(20, 20, 20, 255))
    y += 16
    canvas.alpha_composite(strip, (10, y))

canvas.convert("RGB").save(OUT, quality=93)
print("saved", OUT, canvas.size)
