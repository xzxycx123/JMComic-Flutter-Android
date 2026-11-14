"""第二批资源对照图 + 元数据。"""
import os, json
from PIL import Image, ImageDraw

raw = r"D:\data\product\JMComic\img\_raw"
out = r"D:\data\product\JMComic\docs\cdn\contact_sheet2.png"
pick = [
    "loading_cat.gif", "logo_square_stray.png", "logo_stray_title.png", "logo_new2_2020.png",
    "logo_2019_small.png", "icon_jcoin.png", "icon_potato.png", "icon_potato_big.png",
    "icon_new.png", "icon_hot.png", "icon_week.png", "icon_day.png", "icon_theme.png",
    "icon_bbs.png", "icon_more.png", "sprite_social_media.png",
]
meta = {}
for name in pick:
    p = os.path.join(raw, name)
    if not os.path.exists(p):
        continue
    im = Image.open(p)
    frames = getattr(im, "n_frames", 1)
    meta[name] = {
        "bytes": os.path.getsize(p), "format": im.format, "size": list(im.size),
        "mode": im.mode, "frames": frames,
        "duration_ms": im.info.get("duration"),
    }

rows = []
for name in pick:
    p = os.path.join(raw, name)
    if not os.path.exists(p):
        continue
    im = Image.open(p)
    if getattr(im, "n_frames", 1) > 1:
        im.seek(0)
    im = im.convert("RGBA")
    rows.append((name, im))

W = 760
LABEL = 20
# 两列布局
col_w = W // 2
positions = []
y0 = 12
col_y = [y0, y0]
for name, im in rows:
    scale = min(1.0, (col_w - 24) / im.width, 220 / im.height)
    w, h = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    positions.append((name, im, w, h))

total_h = 12
heights = [12, 12]
for name, im, w, h in positions:
    c = 0 if heights[0] <= heights[1] else 1
    heights[c] += h + LABEL + 10
    total_h = max(heights)
canvas = Image.new("RGBA", (W, total_h + 12), (250, 250, 250, 255))
d = ImageDraw.Draw(canvas)
cy = [12, 12]
for name, im, w, h in positions:
    c = 0 if cy[0] <= cy[1] else 1
    x = c * col_w + 12
    d.text((x, cy[c]), name, fill=(30, 30, 30, 255))
    cy[c] += LABEL
    canvas.alpha_composite(im.resize((w, h), Image.LANCZOS), (x, cy[c]))
    cy[c] += h + 10

canvas.convert("RGB").save(out, quality=92)
print(json.dumps(meta, ensure_ascii=False, indent=2))
print("sheet:", out, canvas.size)
