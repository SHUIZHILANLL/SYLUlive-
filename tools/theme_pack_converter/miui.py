"""MIUI/HyperOS 主题包（.mtheme 解包目录）只读解析。

模块 = 根目录下一个无扩展名文件（真实格式是 ZIP），名字是 Android 包名。
模块内可能包含 theme_values.xml（资源名覆盖）、theme_fallback.xml（暗色回落）、
res/drawable-*/（位图）、nightmode/（深色一套）。
"""

from __future__ import annotations

import collections
import os
import re
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

COLOR_RE = re.compile(r'<color\s+name="([^"]+)"\s*>([^<]+)</color>')
COLOR_VALUE_RE = re.compile(r"#[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?")

# 语义名 → 我们的 token。只有命中这些的资源名才参与主色推断。
ACCENT_NAME_HINTS = (
    "accent_color",
    "design_default_color_primary",
    "coloraccent",
    "progress_primary",
    "cc_qs_tile_icon_color",
    "control_center_universal_enabled_color",
    "miui_volume_color_btn_seleted",
)

BASE_NAMES = {"#FF000000", "#FFFFFFFF", "#00000000", "#00FFFFFF"}

# 根目录里不是模块的文件后缀（description.xml、预览图等）
NON_MODULE_SUFFIXES = {".xml", ".jpg", ".jpeg", ".png", ".webp", ".gif", ".json", ".txt", ".md"}


@dataclass
class ModuleInfo:
    name: str
    theme_value_files: int = 0
    color_count: int = 0
    colors: collections.Counter = field(default_factory=collections.Counter)
    names: dict[str, str] = field(default_factory=dict)


@dataclass
class ThemeScan:
    root: Path
    modules: dict[str, ModuleInfo] = field(default_factory=dict)
    colors: collections.Counter = field(default_factory=collections.Counter)
    names: dict[str, str] = field(default_factory=dict)

    def brand_candidates(self) -> list[dict]:
        """按「语义名命中 + 全局出现次数」给候选主色排序。"""
        scored: dict[str, dict] = {}
        for module, info in self.modules.items():
            for name, value in info.names.items():
                low = name.lower()
                if not any(h in low for h in ACCENT_NAME_HINTS):
                    continue
                if value in BASE_NAMES:
                    continue
                entry = scored.setdefault(
                    value, {"color": value, "weight": 0, "names": set(), "modules": set()}
                )
                entry["weight"] += self.colors.get(value, 1)
                entry["names"].add(name)
                entry["modules"].add(module)
        out = []
        for entry in scored.values():
            out.append(
                {
                    "color": entry["color"],
                    "global_count": self.colors[entry["color"]],
                    "semantic_hits": len(entry["names"]),
                    "modules": len(entry["modules"]),
                    "sample_names": sorted(entry["names"])[:3],
                }
            )
        # 语义命中优先，其次全局权重
        out.sort(key=lambda e: (-e["semantic_hits"], -e["global_count"]))
        return out


def _read_zip_text(zf: zipfile.ZipFile, name: str) -> str:
    try:
        return zf.read(name).decode("utf-8", "ignore")
    except Exception:
        return ""


def scan(root: str | Path) -> ThemeScan:
    root = Path(root)
    result = ThemeScan(root=root)
    for entry in sorted(os.listdir(root)):
        path = root / entry
        # 模块名本身含点（com.miui.home），不能按 suffix 判定，只排除已知的非模块文件
        if not path.is_file() or path.suffix.lower() in NON_MODULE_SUFFIXES:
            continue
        try:
            zf = zipfile.ZipFile(path)
        except zipfile.BadZipFile:
            continue
        with zf:
            tv_files = [n for n in zf.namelist() if n.endswith("theme_values.xml")]
            if not tv_files:
                continue
            info = ModuleInfo(name=entry, theme_value_files=len(tv_files))
            for member in tv_files:
                for raw_name, raw_value in COLOR_RE.findall(_read_zip_text(zf, member)):
                    value = raw_value.strip().upper()
                    if not COLOR_VALUE_RE.fullmatch(value):
                        continue
                    if len(value) == 7:  # #RRGGBB → #AARRGGBB
                        value = "#FF" + value[1:]
                    info.colors[value] += 1
                    info.names.setdefault(raw_name, value)
                    info.color_count += 1
            result.modules[entry] = info
            result.colors.update(info.colors)
            for name, value in info.names.items():
                result.names.setdefault(name, value)
    return result


def read_asset(root: str | Path, *candidates: str) -> bytes | None:
    """按候选顺序在模块内取第一个存在的资产。candidates 形如 "com.miui.home:res/x.png"。"""
    root = Path(root)
    for cand in candidates:
        module, _, member = cand.partition(":")
        path = root / module
        if not module or not path.is_file():
            continue
        try:
            with zipfile.ZipFile(path) as zf:
                try:
                    return zf.read(member)
                except KeyError:
                    continue
        except zipfile.BadZipFile:
            continue
    return None


def wallpaper_sources(root: str | Path) -> dict[str, bytes]:
    """返回 {用途: 原始字节}。优先根目录 wallpaper/，其次模块内嵌默认壁纸。"""
    root = Path(root)
    out: dict[str, bytes] = {}
    for name, key in (("default_wallpaper.jpg", "portrait"), ("default_lock_wallpaper.jpg", "lock")):
        path = root / "wallpaper" / name
        if path.is_file():
            out[key] = path.read_bytes()
    if "portrait" not in out:
        embedded = read_asset(
            root,
            "framework-res:res/drawable-xhdpi/default_wallpaper.jpg",
            "framework-res:res/drawable-xxhdpi/default_wallpaper.jpg",
        )
        if embedded:
            out["portrait"] = embedded
    return out


PREVIEW_ORDER = (
    "preview_launcher_0",
    "preview_lockscreen_0",
    "preview_statusbar_0",
    "preview_settings_0",
    "preview_mms_0",
    "preview_contact_0",
)


def preview_sources(root: str | Path) -> dict[str, bytes]:
    root = Path(root) / "preview"
    out: dict[str, bytes] = {}
    if not root.is_dir():
        return out
    files = {p.stem: p for p in root.iterdir() if p.is_file() and p.suffix.lower() in (".jpg", ".jpeg", ".png")}
    for stem in PREVIEW_ORDER:
        path = files.get(stem)
        if path:
            out[stem] = path.read_bytes()
    for stem, path in sorted(files.items()):  # 补足到 8 张
        if len(out) >= 8:
            break
        out.setdefault(stem, path.read_bytes())
    return out


def icon_codepoints(module_root: str | Path) -> int:
    """icons 模块里的图标数量（仅用于报告；Android 包名图标不进入 App）。"""
    path = Path(module_root) / "icons"
    if not path.is_file():
        return 0
    try:
        with zipfile.ZipFile(path) as zf:
            return sum(1 for n in zf.namelist() if n.lower().endswith(".png"))
    except zipfile.BadZipFile:
        return 0


def read_description(theme_root: str | Path) -> dict:
    """读 description.xml 的元信息，用于批量转换时自动填 name/author/版本。"""
    path = Path(theme_root) / "description.xml"
    if not path.is_file():
        return {}
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return {}
    out: dict = {}
    for key in ("title", "designer", "author", "version", "miuiVersion", "uiVersion", "editorVersion"):
        match = re.search(rf"<{key}>(.*?)</{key}>", text, re.S)
        if match:
            value = re.sub(r"\s+", " ", match.group(1)).strip()
            if value:
                out[key] = value
    return out


def looks_like_theme(theme_root: str | Path) -> bool:
    """判断一个目录像不像解包后的主题包：有 description.xml 且至少 3 个无扩展名模块。"""
    root = Path(theme_root)
    if not root.is_dir() or not (root / "description.xml").is_file():
        return False
    modules = [
        p
        for p in root.iterdir()
        if p.is_file() and p.suffix.lower() not in NON_MODULE_SUFFIXES and p.stat().st_size > 1024
    ]
    return len(modules) >= 3
