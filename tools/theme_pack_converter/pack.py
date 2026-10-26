"""主题包组装与校验：tokens 白名单、manifest、sha256、zip 打包。"""

from __future__ import annotations

import hashlib
import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import colorutil as cu

SCHEMA_VERSION = 1
PACK_SUFFIX = ".syltheme"

# ---- tokens 白名单（超出即拒绝导入，与 App 侧保持同步）----------------------
ALLOWED_TOKENS = {
    # 背景与表面
    "bg.primary",
    "surface.primary",
    "surface.secondary",
    "surface.elevated",
    # 文字与边框
    "text.primary",
    "text.secondary",
    "text.disabled",
    "border.normal",
    "border.subtle",
    # 品牌与强调
    "brand.primary",
    "accent.secondary",
    "tag.bg",
    "tag.text",
    "message.outgoing",
    "composer.input",
    # 圆角（0.5x – 2x）
    "radius.sm",
    "radius.md",
    "radius.lg",
    "radius.sheet",
    # 外观预设
}

# 永不可覆盖：状态语义色、pill 圆角、全部间距
FORBIDDEN_PREFIXES = ("success", "warning", "danger", "info", "spacing")
FORBIDDEN_EXACT = {"radius.pill"}

RADIUS_DEFAULTS = {"radius.sm": 8.0, "radius.md": 12.0, "radius.lg": 16.0, "radius.sheet": 24.0}
RADIUS_MIN_FACTOR, RADIUS_MAX_FACTOR = 0.5, 2.0


class PackError(ValueError):
    pass


@dataclass
class PackAsset:
    path: str
    data: bytes

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.data).hexdigest()


@dataclass
class PackDraft:
    pack_id: str
    name: str
    version: str
    min_app_version: str
    source: str
    author: str
    license: str
    license_text: str
    tokens: dict
    assets: list[PackAsset] = field(default_factory=list)
    previews: list[PackAsset] = field(default_factory=list)
    capabilities: dict = field(default_factory=dict)
    notes: dict = field(default_factory=dict)


def validate_tokens(tokens: dict) -> list[str]:
    """返回问题列表；空列表表示通过。"""
    problems: list[str] = []
    if set(tokens) - {"light", "dark"}:
        problems.append(f"tokens 顶层只允许 light/dark，发现 {sorted(set(tokens) - {'light', 'dark'})}")
    for mode, block in tokens.items():
        if mode not in ("light", "dark"):
            continue
        if not isinstance(block, dict):
            problems.append(f"{mode} 必须是对象")
            continue
        for key, value in block.items():
            if key in FORBIDDEN_EXACT or key.startswith(FORBIDDEN_PREFIXES):
                problems.append(f"{mode}.{key} 属不可覆盖项")
                continue
            if key not in ALLOWED_TOKENS:
                problems.append(f"{mode}.{key} 不在白名单内")
                continue
            if key.startswith("radius."):
                base = RADIUS_DEFAULTS[key]
                if not isinstance(value, (int, float)):
                    problems.append(f"{mode}.{key} 必须是数字")
                    continue
                if not (base * RADIUS_MIN_FACTOR <= float(value) <= base * RADIUS_MAX_FACTOR):
                    problems.append(
                        f"{mode}.{key}={value} 超出允许范围 "
                        f"{base * RADIUS_MIN_FACTOR}–{base * RADIUS_MAX_FACTOR}"
                    )
                continue
            if not isinstance(value, str) or not value.startswith("#"):
                problems.append(f"{mode}.{key} 必须是 #AARRGGBB 字符串")
    return problems


def build_tokens(brand: str, accent: str | None = None, *, bg_light: str = cu.DEFAULT_BG_LIGHT,
                 bg_dark: str = cu.DEFAULT_BG_DARK) -> tuple[dict, dict]:
    """由主色推出 light/dark 两套 tokens，并返回报告用的调整说明。

    对比度约定（ADR-003 草案）：
      - brand.primary 用于色块/按钮底：与页面底色 ≥ 3:1
      - tag.bg 是 brand 的柔化底色；tag.text 是「把品牌色当文字用」时的合规替代，
        与 tag.bg ≥ 4.5:1
    """
    report: dict = {}

    light_brand, fixed_light = cu.ensure_contrast(brand, bg_light, cu.LARGE_MIN_RATIO)
    dark_brand = cu.lighten_for_dark(brand, bg_dark, cu.LARGE_MIN_RATIO)

    tag_bg_light = cu.blend(light_brand, bg_light, 0.22)
    tag_bg_dark = cu.blend(dark_brand, bg_dark, 0.28)
    tag_text_light, fixed_tag_light = cu.ensure_contrast(light_brand, tag_bg_light, cu.TEXT_MIN_RATIO)
    tag_text_dark, fixed_tag_dark = cu.ensure_contrast(dark_brand, tag_bg_dark, cu.TEXT_MIN_RATIO)

    light = {
        "brand.primary": light_brand,
        "brand.onPrimary": cu.best_on_color(light_brand),
        "tag.bg": tag_bg_light,
        "tag.text": tag_text_light,
    }
    dark = {
        "brand.primary": dark_brand,
        "brand.onPrimary": cu.best_on_color(dark_brand),
        "tag.bg": tag_bg_dark,
        "tag.text": tag_text_dark,
    }
    # brand.onPrimary 不在白名单（由 App 算法决定），这里只用于报告
    report["brand_input"] = brand
    report["brand_light"] = light_brand
    report["brand_dark"] = dark_brand
    report["brand_light_adjusted"] = fixed_light
    report["contrast_light_bg"] = round(cu.contrast_ratio(light_brand, bg_light), 2)
    report["contrast_dark_bg"] = round(cu.contrast_ratio(dark_brand, bg_dark), 2)
    report["tag_text_light"] = tag_text_light
    report["tag_text_light_adjusted"] = fixed_tag_light
    report["contrast_tag_light"] = round(cu.contrast_ratio(tag_text_light, tag_bg_light), 2)
    report["tag_text_dark"] = tag_text_dark
    report["contrast_tag_dark"] = round(cu.contrast_ratio(tag_text_dark, tag_bg_dark), 2)
    report["on_primary_light"] = cu.best_on_color(light_brand)
    report["on_primary_dark"] = cu.best_on_color(dark_brand)

    if accent:
        accent_light, fixed_accent = cu.ensure_contrast(accent, bg_light, cu.LARGE_MIN_RATIO)
        # 修正幅度过大说明这个颜色在浅底上"不可能合规"，宁可不写也不要悄悄变色
        delta = abs(cu.lightness(accent_light) - cu.lightness(accent))
        report["accent_input"] = accent
        report["accent_adjusted"] = fixed_accent
        report["accent_lightness_delta"] = round(delta, 3)
        if delta > 0.25:
            report.setdefault("warnings", []).append(
                f"次强调色 {accent} 在浅底上需要移动 {delta:.0%} 亮度才合规，已丢弃该 token（避免主题变色）"
            )
        else:
            light["accent.secondary"] = accent_light
        dark["accent.secondary"] = cu.lighten_for_dark(accent, bg_dark, cu.LARGE_MIN_RATIO)

    # 只保留白名单键（brand.onPrimary 交回 App 计算）
    light = {k: v for k, v in light.items() if k in ALLOWED_TOKENS}
    dark = {k: v for k, v in dark.items() if k in ALLOWED_TOKENS}
    return {"light": light, "dark": dark}, report


def _manifest(draft: PackDraft) -> dict:
    assets = [
        {"path": a.path, "sha256": a.sha256, "bytes": len(a.data)} for a in draft.assets
    ]
    previews = [
        {"path": a.path, "sha256": a.sha256, "bytes": len(a.data)} for a in draft.previews
    ]
    total = sum(a["bytes"] for a in assets) + sum(a["bytes"] for a in previews)
    manifest = {
        "schema": SCHEMA_VERSION,
        "id": draft.pack_id,
        "name": draft.name,
        "version": draft.version,
        "minAppVersion": draft.min_app_version,
        "source": draft.source,
        "author": draft.author,
        "license": draft.license,
        "licenseText": draft.license_text,
        "bytes": total,
        "assets": assets,
        "preview": previews,
        "capabilities": draft.capabilities,
    }
    if draft.notes:
        manifest["notes"] = draft.notes
    return manifest


def write_pack(draft: PackDraft, out_path: str | Path) -> dict:
    """写出 .syltheme（zip：manifest.json + tokens.json + assets/*）。返回 manifest。"""
    problems = validate_tokens(draft.tokens)
    if problems:
        raise PackError("tokens 校验失败:\n  - " + "\n  - ".join(problems))

    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    manifest = _manifest(draft)

    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        def add(name: str, data: bytes) -> None:
            info = zipfile.ZipInfo(name)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, data)

        add("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2).encode("utf-8"))
        add("tokens.json", json.dumps(draft.tokens, ensure_ascii=False, indent=2).encode("utf-8"))
        for asset in draft.assets + draft.previews:
            add(asset.path, asset.data)
    return manifest


def verify_pack(path: str | Path) -> dict:
    """重新打开包做独立校验：schema、白名单、逐资产 sha256。"""
    path = Path(path)
    result = {"path": str(path), "bytes": path.stat().st_size, "problems": []}
    with zipfile.ZipFile(path) as zf:
        names = set(zf.namelist())
        manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
        result["id"] = manifest.get("id")
        result["version"] = manifest.get("version")
        if manifest.get("schema") != SCHEMA_VERSION:
            result["problems"].append(f"schema 期望 {SCHEMA_VERSION}，实际 {manifest.get('schema')}")
        if "tokens.json" not in names:
            result["problems"].append("缺 tokens.json")
        else:
            tokens = json.loads(zf.read("tokens.json").decode("utf-8"))
            result["problems"].extend(validate_tokens(tokens))
        for item in manifest.get("assets", []) + manifest.get("preview", []):
            if item["path"] not in names:
                result["problems"].append(f"声明了但包内缺失: {item['path']}")
                continue
            digest = hashlib.sha256(zf.read(item["path"])).hexdigest()
            if digest != item["sha256"]:
                result["problems"].append(f"sha256 不匹配: {item['path']}")
    return result
