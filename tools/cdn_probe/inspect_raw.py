"""检查抓到的 JM 图标资源尺寸/透明度，输出清单。"""
import sys, os, json
from PIL import Image

raw = r"D:\data\product\JMComic\img\_raw"
rows = []
for name in sorted(os.listdir(raw)):
    path = os.path.join(raw, name)
    try:
        im = Image.open(path)
        info = {
            "file": name,
            "bytes": os.path.getsize(path),
            "format": im.format,
            "size": list(im.size),
            "mode": im.mode,
        }
        if im.format == "ICO":
            info["ico_sizes"] = sorted({s[0] for s in im.info.get("sizes", set())})
        if im.mode in ("RGBA", "LA", "P"):
            im2 = im.convert("RGBA")
            alpha = im2.getchannel("A")
            bbox = alpha.getbbox()
            info["content_bbox"] = list(bbox) if bbox else None
        rows.append(info)
    except Exception as e:
        rows.append({"file": name, "error": str(e)})

print(json.dumps(rows, ensure_ascii=False, indent=2))
