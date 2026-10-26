"""颜色工具：hex 解析、相对亮度、WCAG 对比度、按对比度自动修正。"""

from __future__ import annotations

import colorsys

# App 侧的默认底色（与 client/lib/theme/app_colors.dart 保持一致），用于对比度校验。
DEFAULT_BG_LIGHT = "#FFFAF4"
DEFAULT_BG_DARK = "#111315"

TEXT_MIN_RATIO = 4.5      # 正文
LARGE_MIN_RATIO = 3.0     # 大色块 / 图标


def parse_hex(value: str) -> tuple[int, int, int, int]:
    """'#AARRGGBB' 或 '#RRGGBB' → (a, r, g, b)。"""
    v = value.strip().lstrip("#")
    if len(v) == 6:
        v = "FF" + v
    if len(v) != 8:
        raise ValueError(f"非法颜色: {value}")
    a, r, g, b = (int(v[i : i + 2], 16) for i in (0, 2, 4, 6))
    return a, r, g, b


def to_hex(a: int, r: int, g: int, b: int) -> str:
    return f"#{a:02X}{r:02X}{g:02X}{b:02X}"


def to_hex_rgb(rgb: tuple[int, int, int], alpha: int = 0xFF) -> str:
    return to_hex(alpha, *rgb)


def _srgb_channel(c: int) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(value: str) -> float:
    _, r, g, b = parse_hex(value)
    return 0.2126 * _srgb_channel(r) + 0.7152 * _srgb_channel(g) + 0.0722 * _srgb_channel(b)


def contrast_ratio(fg: str, bg: str) -> float:
    lf, lb = relative_luminance(fg), relative_luminance(bg)
    hi, lo = max(lf, lb), min(lf, lb)
    return (hi + 0.05) / (lo + 0.05)


def best_on_color(bg: str) -> str:
    """在纯黑/纯白里挑对比度更高者作为前景色。"""
    black, white = "#FF000000", "#FFFFFFFF"
    return white if contrast_ratio(white, bg) >= contrast_ratio(black, bg) else black


def _hls(value: str):
    _, r, g, b = parse_hex(value)
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    return h, l, s


def adjust_lightness(value: str, target_l: float) -> str:
    h, _, s = _hls(value)
    r, g, b = colorsys.hls_to_rgb(h, max(0.0, min(1.0, target_l)), s)
    return to_hex_rgb((round(r * 255), round(g * 255), round(b * 255)))


def lightness(value: str) -> float:
    _, l, _ = _hls(value)
    return l


def ensure_contrast(value: str, bg: str, minimum: float = TEXT_MIN_RATIO) -> tuple[str, bool]:
    """把 value 沿亮度轴移动，直到与 bg 的对比度达标。返回 (颜色, 是否被修改)。"""
    if contrast_ratio(value, bg) >= minimum:
        return value, False
    _, l, _ = _hls(value)
    bg_lum = relative_luminance(bg)
    # 背景亮 → 往暗处走；背景暗 → 往亮处走
    direction = -1 if bg_lum > 0.5 else 1
    best = value
    for step in range(1, 101):
        candidate_l = max(0.0, min(1.0, l + direction * step / 100))
        candidate = adjust_lightness(value, candidate_l)
        best = candidate
        if contrast_ratio(candidate, bg) >= minimum:
            return candidate, True
    return best, True


def lighten_for_dark(value: str, bg: str = DEFAULT_BG_DARK, minimum: float = TEXT_MIN_RATIO) -> str:
    """深色模式下的品牌色：提亮到在深底上可用。"""
    adjusted, _ = ensure_contrast(value, bg, minimum)
    return adjusted


def blend(top: str, bottom: str, alpha: float) -> str:
    """把 top 以 alpha 叠在 bottom 上（不透明结果），用于生成 soft tint 背景。"""
    _, tr, tg, tb = parse_hex(top)
    _, br, bg_, bb = parse_hex(bottom)
    a = max(0.0, min(1.0, alpha))
    r = round(tr * a + br * (1 - a))
    g = round(tg * a + bg_ * (1 - a))
    b = round(tb * a + bb * (1 - a))
    return to_hex_rgb((r, g, b))
