"""把抓到的原始资源拼成一张对照图，便于肉眼确认（不含任何相册内容）。"""
import os
from PIL import Image

raw = r"D:\data\product\JMComic\img\_raw"
out = r"D:\data\product\JMComic\docs\cdn\contact_sheet.png"
files = [f for f in sorted(os.listdir(raw)) if f.lower().endswith((".png", ".ico"))]

tiles = []
for f in files:
    im = Image.open(os.path.join(raw, f)).convert("RGBA")
    tiles.append((f, im))

# 棋盘底 + 标签条
W = 900
pad, label_h = 16, 22
total_h = sum(t[1].height + label_h + pad for t in tiles) + pad
canvas = Image.new("RGBA", (W, total_h), (255, 255, 255, 255))
y = pad
from PIL import ImageDraw
d = ImageDraw.Draw(canvas)
for name, im in tiles:
    d.text((pad, y), name, fill=(20, 20, 20, 255))
    y += label_h
    cw = min(im.width, W - 2 * pad)
    scale = cw / im.width
    shown = im.resize((int(im.width * scale), max(1, int(im.height * scale))), Image.LANCZOS)
    canvas.alpha_composite(shown, (pad, y))
    y += shown.height + pad

canvas.convert("RGB").save(out, quality=92)
print("saved", out, canvas.size)
