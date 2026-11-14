"""把加载动画的灰底抠成透明，导出透明版 gif + 首帧 PNG。"""
import os
from PIL import Image

IMG = r"D:\data\product\JMComic\img\loading"
src_path = os.path.join(IMG, "loading_cat_480.gif")
src = Image.open(src_path)

frames, durations = [], []
for i in range(src.n_frames):
    src.seek(i)
    frames.append(src.convert("RGBA"))
    durations.append(src.info.get("duration", 70))

# 采样左上角判断底色
bg = frames[0].getpixel((2, 2))
print("background sample:", bg)


def drop_bg(im, tol=18):
    px = im.load()
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    opx = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and abs(r - bg[0]) <= tol and abs(g - bg[1]) <= tol and abs(b - bg[2]) <= tol:
                continue
            opx[x, y] = (r, g, b, a)
    return out


trans_frames = [drop_bg(f) for f in frames]


def save_gif(frames_rgba, target_w, name, note_bytes_note=""):
    if target_w:
        ratio = target_w / frames_rgba[0].width
        size = (target_w, max(1, int(frames_rgba[0].height * ratio)))
        fr = [f.resize(size, Image.LANCZOS) for f in frames_rgba]
    else:
        fr = frames_rgba
    # RGBA -> 带透明索引的调色板
    pal = [f.convert("RGB").quantize(colors=127, method=Image.MEDIANCUT) for f in fr]
    for p, f in zip(pal, fr):
        p.paste(255, mask=f.getchannel("A").point(lambda v: 255 if v < 128 else 0))
    out = os.path.join(IMG, name)
    pal[0].save(out, save_all=True, append_images=pal[1:], duration=durations,
                loop=0, optimize=True, disposal=2, transparency=255)
    print(f"saved {name} {os.path.getsize(out)/1024:.1f}KB {pal[0].size}")


save_gif(trans_frames, 0, "loading_cat_480_alpha.gif")
save_gif(trans_frames, 160, "loading_cat_160_alpha.gif")
save_gif(trans_frames, 96, "loading_cat_96_alpha.gif")
trans_frames[0].save(os.path.join(IMG, "loading_cat_frame1_alpha.png"))
print("saved loading_cat_frame1_alpha.png")
