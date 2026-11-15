"""把 img/ 下的品牌素材整理成 Flutter 可直接引用的位图，并派生 Android 启动图标 / 启动屏图。

用法（在工程根目录）：
    python tools/build_app_assets.py

产出：
    assets/images/*.png|gif                      Flutter 资产（位图只放这里，图标位仍用 assets/icons/*.svg）
    android/.../mipmap-*/ic_launcher.png         桌面图标（48/72/96/144/192）
    android/.../drawable-nodpi/splash_logo.png   启动屏居中图（256，避免直接引用 mipmap）

尺寸策略：所有位图按"最大显示尺寸 × ~2x"给，不看原始 512/1000 大图，控制 APK 体积。
注意：img/brand/brand.png 的容器是 PNG 扩展名但内容是 WebP，这里统一转成真 PNG。
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
IMG = ROOT / "img"
OUT = ROOT / "assets" / "images"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
MIPMAPS = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}


def save_image(
    src: Path,
    dst: Path,
    *,
    width: int | None = None,
    height: int | None = None,
    square: int | None = None,
) -> None:
    with Image.open(src) as image:
        frame = image.convert("RGBA")
        if square is not None:
            frame = frame.resize((square, square), Image.LANCZOS)
        elif width is not None or height is not None:
            ratio = frame.width / frame.height
            if width is not None and height is None:
                height = max(1, round(width / ratio))
            elif height is not None and width is None:
                width = max(1, round(height * ratio))
            frame = frame.resize((width, height), Image.LANCZOS)
        dst.parent.mkdir(parents=True, exist_ok=True)
        frame.save(dst, "PNG", optimize=True)
    print(f"png  {dst.relative_to(ROOT)}  {frame.width}x{frame.height}")


def copy_file(src: Path, dst: Path) -> None:
    shutil.copyfile(src, dst)
    print(f"copy {dst.relative_to(ROOT)}  <- {src.relative_to(ROOT)}")


def save_brand_mark(src: Path, dst: Path, *, square: int = 128, mark_width: int = 300) -> None:
    """从横版合成图里切出左侧方形 mark（首页 AppBar 图标用）。

    `img/brand/brand.png` 是 1000x400 的「mark + 禁漫天堂/18comic 文字」合成图，
    直接缩到 28dp 会把文字压成噪点；这里按 alpha 通道取左侧 mark 的紧边界，
    再居中补成正方形后缩放。
    """
    with Image.open(src) as image:
        frame = image.convert("RGBA")
    box = frame.crop((0, 0, mark_width, frame.height)).getbbox()
    if box is None:
        raise ValueError(f"{src} 左侧没有可用的 mark 像素")
    mark = frame.crop(box)
    side = max(mark.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2))
    canvas = canvas.resize((square, square), Image.LANCZOS)
    dst.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(dst, "PNG", optimize=True)
    print(f"mark {dst.relative_to(ROOT)}  {square}x{square}  <- {src.relative_to(ROOT)} box={box}")


def build_flutter_assets() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    # 方形吉祥物：最大显示 56dp，96px 足够（5 季 + 默认）
    save_image(IMG / "mascot" / "app_icon_512.png", OUT / "mark_default.png", square=96)
    for season in ("newyear", "halloween", "xmas", "sakura", "pink"):
        save_image(IMG / "mascot" / f"mark_{season}_256.png", OUT / f"mark_{season}.png", square=96)

    # 关于页图标（56dp 展示）
    save_image(IMG / "mascot" / "app_icon_512.png", OUT / "app_icon.png", square=128)

    # 品牌合成图（About 横幅高 96dp）
    save_image(IMG / "brand" / "brand.png", OUT / "brand_banner.png", width=640)

    # 首页 AppBar 的品牌标记：从合成图切左侧方形 mark（26–28dp 展示，128 足够 4x）
    save_brand_mark(IMG / "brand" / "brand.png", OUT / "brand_logo.png", square=128)

    # 加载动画（透明底）：96 小号 + 160 大号 + 静态首帧
    copy_file(IMG / "loading" / "loading_cat_96_alpha.gif", OUT / "loading_cat.gif")
    copy_file(IMG / "loading" / "loading_cat_160_alpha.gif", OUT / "loading_cat_large.gif")
    save_image(IMG / "loading" / "loading_cat_frame1_alpha.png", OUT / "loading_cat_frame.png", width=160)

    # 站点 UI 角标（14–30dp 展示，保持原始 64/48px 已足够；NEW 缩到 48 省体积）
    for name, width in (("icon_new", 48), ("icon_hot", 48), ("icon_day", 48), ("icon_week", 48)):
        save_image(IMG / "ui" / f"{name}.png", OUT / f"badge_{name.removeprefix('icon_')}.png", width=width)

    # 火箭（空态主图，最大 92dp）
    save_image(IMG / "ui" / "icon_rocket_280.png", OUT / "rocket.png", width=192)

    # 官方 APP 二维码（96dp 展示 → 192 保证扫码清晰度）
    save_image(IMG / "ui" / "qr_app.png", OUT / "qr_app.png", width=192)


def build_launcher_icons() -> None:
    source = IMG / "mascot" / "app_icon_512.png"
    if not source.exists():
        print(f"跳过桌面图标：缺少 {source.relative_to(ROOT)}", file=sys.stderr)
        return
    for folder, size in MIPMAPS.items():
        target_dir = RES / folder
        if not target_dir.exists():
            continue
        save_image(source, target_dir / "ic_launcher.png", square=size)

    # 启动屏用独立 drawable（不直接引用 mipmap：将来加自适应图标时 XML 无法当 bitmap 用）
    splash = RES / "drawable-nodpi" / "splash_logo.png"
    save_image(source, splash, square=256)


def main() -> int:
    if not IMG.exists():
        print("缺少 img/ 目录", file=sys.stderr)
        return 1
    build_flutter_assets()
    build_launcher_icons()
    print("done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
