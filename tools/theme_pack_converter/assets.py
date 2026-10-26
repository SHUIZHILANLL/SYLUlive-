"""位图资产处理：壁纸与预览图的缩放、裁切、压缩。"""

from __future__ import annotations

import io
from dataclasses import dataclass

from PIL import Image, ImageChops, ImageDraw, ImageFilter

PORTRAIT_SIZE = (1080, 2400)
LANDSCAPE_SIZE = (2400, 1080)
PREVIEW_MAX_SIDE = 720


@dataclass
class PackedImage:
    data: bytes
    width: int
    height: int
    fmt: str

    @property
    def bytes(self) -> int:
        return len(self.data)


def _open(raw: bytes) -> Image.Image:
    img = Image.open(io.BytesIO(raw))
    img.load()
    if img.mode not in ("RGB", "L"):
        img = img.convert("RGB")
    elif img.mode == "L":
        img = img.convert("RGB")
    return img


def _cover_resize(img: Image.Image, target: tuple[int, int]) -> Image.Image:
    """等比缩放后居中裁切（cover 语义），避免壁纸变形。"""
    tw, th = target
    w, h = img.size
    scale = max(tw / w, th / h)
    nw, nh = max(tw, round(w * scale)), max(th, round(h * scale))
    img = img.resize((nw, nh), Image.LANCZOS)
    left = (nw - tw) // 2
    top = (nh - th) // 2
    return img.crop((left, top, left + tw, top + th))


def pack_wallpaper(raw: bytes, target: tuple[int, int] = PORTRAIT_SIZE, quality: int = 85) -> PackedImage:
    img = _cover_resize(_open(raw), target)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality, optimize=True, progressive=True)
    return PackedImage(buf.getvalue(), img.width, img.height, "jpeg")


def pack_preview(raw: bytes, quality: int = 82) -> PackedImage:
    img = _open(raw)
    img.thumbnail((PREVIEW_MAX_SIDE, PREVIEW_MAX_SIDE * 3), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=quality, optimize=True)
    return PackedImage(buf.getvalue(), img.width, img.height, "jpeg")


def dominant_colors(raw: bytes, count: int = 3) -> list[str]:
    """壁纸主色（量化后取占比最高的几个），用于报告与配色参考。"""
    img = _open(raw)
    img.thumbnail((160, 160))
    quant = img.quantize(colors=count, method=Image.Quantize.MEDIANCUT)
    palette = quant.getpalette() or []
    counts = sorted(quant.getcolors() or [], reverse=True)
    out = []
    for _, index in counts[:count]:
        r, g, b = palette[index * 3 : index * 3 + 3]
        out.append(f"#{r:02X}{g:02X}{b:02X}")
    return out

# --------------------------------------------------------------------------- 角色抠图
# 主题包里的角色立绘是"实色圆角底 + 角色"（ic_qs_big_tile_bg_*）。
# 直接当空态插画会带一块紫底。做法：
#   1) 与底色做全局差值 → 内容遮罩；
#   2) 形态学闭运算填掉头发里的细小孔洞（避免把浅色头发抠穿）；
#   3) 只保留最大连通块，丢掉角落装饰与文字碎片；
#   4) 裁到内容外接框 → 补成正方形 → 512。
# 注：不用"从四边泛洪"——圆角底会让泛洪进不去内部。

MASCOT_SIZE = 512
MASCOT_WORK_WIDTH = 900
MASCOT_BG_TOLERANCE = 40


def _bg_color(img: Image.Image) -> tuple[int, int, int]:
    """自动判底色：近黑占比高 → 黑底（AOD 帧）；否则取左侧中间像素。"""
    w, h = img.size
    hist = img.convert('L').histogram()
    near_black = sum(hist[:24])
    total = w * h
    if total and near_black / total > 0.4:
        return (0, 0, 0)
    return img.getpixel((max(1, int(w * 0.05)), h // 2))[:3]


def _content_mask(rgb: Image.Image, bg: tuple[int, int, int], tol: int) -> Image.Image:
    solid = Image.new('RGB', rgb.size, bg)
    diff = ImageChops.difference(rgb, solid).convert('L')
    mask = diff.point(lambda v: 0 if v <= tol else 255)
    # 闭运算：先膨胀后腐蚀，填掉头发里的细孔
    mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))
    return mask


def _largest_component(mask: Image.Image) -> Image.Image:
    w, h = mask.size
    data = mask.load()
    seen = bytearray(w * h)
    best: list[int] = []
    for start in range(w * h):
        if data[start % w, start // w] == 0 or seen[start]:
            continue
        comp: list[int] = []
        stack = [start]
        seen[start] = 1
        while stack:
            i = stack.pop()
            comp.append(i)
            x, y = i % w, i // w
            for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if not seen[j] and data[nx, ny] != 0:
                        seen[j] = 1
                        stack.append(j)
        if len(comp) > len(best):
            best = comp
    out = Image.new('L', (w, h), 0)
    od = out.load()
    for i in best:
        od[i % w, i // w] = 255
    return out


def pack_mascot(raw: bytes, size: int = MASCOT_SIZE, tolerance: int = MASCOT_BG_TOLERANCE,
                force_bg: tuple[int, int, int] | None = None) -> PackedImage:
    """角色图 → 透明底方形 PNG（空态插画用）。"""
    src = Image.open(io.BytesIO(raw))
    src.load()
    src = src.convert('RGB')

    work_w = min(MASCOT_WORK_WIDTH, src.width)
    work = src.resize((work_w, round(src.height * work_w / src.width)), Image.LANCZOS)

    bg = force_bg if force_bg is not None else _bg_color(work)
    mask = _content_mask(work, bg, tolerance)
    mask = _largest_component(mask)
    # 硬阈值：把羽化/键控产生的半透明像素二值化。
    # 否则浅色区域（白帽子、浅色头发）会残留大片半透明像素，
    # 贴到界面上看起来像"整张图透明"。只留 1px 抗锯齿。
    mask = mask.point(lambda v: 255 if v >= 110 else 0)
    mask = mask.filter(ImageFilter.GaussianBlur(0.6))

    alpha_full = mask.resize(src.size, Image.LANCZOS)
    rgba = src.convert('RGBA')
    rgba.putalpha(alpha_full)

    bbox = alpha_full.getbbox()
    if not bbox:
        return PackedImage(raw, 0, 0, 'png')

    left, top, right, bottom = bbox
    side = max(right - left, bottom - top)
    pad = int(side * 0.05)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    half = side // 2 + pad
    box = (max(0, cx - half), max(0, cy - half), min(src.width, cx + half), min(src.height, cy + half))
    cropped = rgba.crop(box)

    side = max(cropped.size)
    canvas = Image.new('RGBA', (side, side), (0, 0, 0, 0))
    canvas.paste(cropped, ((side - cropped.width) // 2, (side - cropped.height) // 2), cropped)
    canvas = canvas.resize((size, size), Image.LANCZOS)

    # 最终二值化：LANCZOS 缩放会在轮廓带出几像素的半透明，
    # 贴到界面上就是"整张图发虚"。在最终尺寸上再卡一次阈值。
    alpha = canvas.split()[-1].point(lambda v: 255 if v >= 100 else 0)
    canvas.putalpha(alpha)

    # 白色描边：只画在**外轮廓**上。
    # 注意不能直接用膨胀后的 alpha —— 膨胀会把角色内部的透明小洞
    # （眼睛高光、发丝缝隙）一起填成白色，眼睛就"花了"。
    # 所以用 ring = dilate(alpha) - alpha，只保留外侧那一圈。
    grown = alpha.filter(ImageFilter.MaxFilter(5))
    ring = ImageChops.subtract(grown, alpha)
    outline = Image.new('RGBA', canvas.size, (255, 255, 255, 0))
    outline.putalpha(ring)
    outline.alpha_composite(canvas)
    canvas = outline

    buf = io.BytesIO()
    canvas.save(buf, 'PNG', optimize=True)
    return PackedImage(buf.getvalue(), size, size, 'png')

def pack_avatar(
    raw: bytes,
    size: int = MASCOT_SIZE,
    center: tuple[float, float] = (0.49, 0.475),
    crop_ratio: float = 0.34,
) -> PackedImage:
    """从壁纸裁一块圆形头像（不抠图，零残渣）。

    为什么需要它：有些主题的角色是**深色头发**，与 AOD 帧的纯黑底几乎同色，
    按颜色键控必然把头发一起抠掉（脸就"花"了）。
    这类主题改用壁纸裁切 + 圆形遮罩，图案完整、眼睛不会破。
    """
    src = Image.open(io.BytesIO(raw))
    src.load()
    src = src.convert('RGB')
    w, h = src.size

    side = int(min(w, h) * crop_ratio)
    cx = int(w * center[0])
    cy = int(h * center[1])
    left = max(0, min(w - side, cx - side // 2))
    top = max(0, min(h - side, cy - side // 2))
    sq = src.crop((left, top, left + side, top + side)).resize(
        (size, size), Image.LANCZOS
    ).convert('RGBA')

    # 圆形遮罩 + 外侧 2px 白圈
    mask = Image.new('L', (size, size), 0)
    d = ImageDraw.Draw(mask)
    inset = 3
    d.ellipse((inset, inset, size - inset - 1, size - inset - 1), fill=255)
    ring_mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(ring_mask).ellipse((0, 0, size - 1, size - 1), fill=255)

    ring = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    ring.putalpha(ImageChops.subtract(ring_mask, mask))
    body = sq.copy()
    body.putalpha(mask)
    ring.alpha_composite(body)

    buf = io.BytesIO()
    ring.save(buf, 'PNG', optimize=True)
    return PackedImage(buf.getvalue(), size, size, 'png')


def mascot_hole_ratio(packed: PackedImage) -> float:
    """估算抠图"破洞率"：最大连通块外接框内，透明像素占比。"""
    im = Image.open(io.BytesIO(packed.data)).convert('RGBA')
    a = im.split()[-1]
    bbox = a.getbbox()
    if not bbox:
        return 1.0
    region = a.crop(bbox)
    hist = region.histogram()
    total = region.size[0] * region.size[1]
    return hist[0] / total if total else 1.0


def _strip_nine_patch(img: Image.Image) -> Image.Image:
    """9-patch 首尾各 1px 是黑色标记线，用之前必须切掉。"""
    w, h = img.size
    if w <= 2 or h <= 2:
        return img
    return img.crop((1, 1, w - 1, h - 1))


def pack_texture(raw: bytes, width: int = 1080, quality: int = 78) -> PackedImage:
    """卡片/页面纹理：去掉 9-patch 标记、等比缩放、转 JPEG。"""
    img = Image.open(io.BytesIO(raw))
    img.load()
    img = _strip_nine_patch(img.convert('RGB'))
    w, h = img.size
    if w > width:
        img = img.resize((width, round(h * width / w)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, 'JPEG', quality=quality, optimize=True)
    return PackedImage(buf.getvalue(), img.size[0], img.size[1], 'jpg')


def pack_banner(raw: bytes, size: tuple[int, int] = (1600, 762), quality: int = 84) -> PackedImage:
    """详情页横幅：把大磁贴图裁成横向比例。"""
    img = Image.open(io.BytesIO(raw))
    img.load()
    img = img.convert('RGB')
    tw, th = size
    scale = max(tw / img.width, th / img.height)
    resized = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    left = (resized.width - tw) // 2
    top = (resized.height - th) // 2
    out = resized.crop((left, top, left + tw, top + th))
    buf = io.BytesIO()
    out.save(buf, 'JPEG', quality=quality, optimize=True)
    return PackedImage(buf.getvalue(), tw, th, 'jpg')
