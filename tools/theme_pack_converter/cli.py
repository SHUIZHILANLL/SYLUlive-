"""SYLUlive 主题包转换器 · CLI

把 MIUI/HyperOS 主题包（解包后的目录）转换成 SYLUlive 的 .syltheme 主题包。

用法:
    python cli.py inspect  <主题目录>
    python cli.py build    <主题目录> -o <输出目录> [--id shenli-joy13] [--name 名称]
                           [--brand "#FF7B8BCF"] [--font <字体文件>] [--lib <client/lib>]
    python cli.py verify   <包.syltheme>
    python cli.py icons    [--flutter-root <Flutter SDK 根目录>]

约定:
    - 只读输入目录，不修改主题包原件。
    - 输出目录由调用方指定；仓库内不放产物。
    - tokens 只写白名单里、且确实从主题里抽到的键；其余交给 App 回落默认值。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import assets as img
import colorutil as cu
import fontsub
import miui
import pack as packer

DEFAULT_MIN_APP = "1.7.6"
FONT_FAMILY = "sylu_pack_{id}_400"


# --------------------------------------------------------------------------- 报告
def _table(rows: list[list[str]], head: list[str]) -> str:
    widths = [max(len(str(r[i])) for r in [head] + rows) for i in range(len(head))]
    def line(cells):
        return "| " + " | ".join(str(c).ljust(widths[i]) for i, c in enumerate(cells)) + " |"
    sep = "|" + "|".join("-" * (w + 2) for w in widths) + "|"
    return "\n".join([line(head), sep] + [line(r) for r in rows])


def _fmt_mb(n: int) -> str:
    return f"{n / 1024 / 1024:.2f} MB"


# --------------------------------------------------------------------------- inspect
def cmd_inspect(args) -> int:
    scan = miui.scan(args.theme)
    print(f"modules with theme_values.xml: {len(scan.modules)}")
    rows = []
    for name, info in sorted(scan.modules.items(), key=lambda kv: -kv[1].color_count):
        top = ", ".join(f"{c}x{k}" for k, c in info.colors.most_common(2))
        rows.append([name, info.theme_value_files, info.color_count, top])
    print(_table(rows, ["module", "files", "colors", "top"]))

    print("\n=== brand candidates ===")
    cands = scan.brand_candidates()[:6]
    for c in cands:
        print(
            f"  {c['color']}  global={c['global_count']:4d} semantic={c['semantic_hits']:2d} "
            f"modules={c['modules']:2d}  {', '.join(c['sample_names'][:2])}"
        )
    print(f"\nicon pngs in icons module: {miui.icon_codepoints(args.theme)}")
    return 0


# --------------------------------------------------------------------------- build
def cmd_build(args) -> int:
    theme = Path(args.theme)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    scan = miui.scan(theme)
    candidates = scan.brand_candidates()
    if not candidates:
        print("!! 未从主题中抽到主色候选，请用 --brand 指定", file=sys.stderr)
        return 2

    brand = args.brand or candidates[0]["color"]
    brand = brand.upper()
    if not brand.startswith("#"):
        brand = "#" + brand
    if len(brand) == 7:
        brand = "#FF" + brand[1:]

    accent = candidates[1]["color"] if len(candidates) > 1 else None
    if args.accent:
        accent = args.accent.upper()
        if len(accent) == 7:
            accent = "#FF" + accent[1:]

    tokens, token_report = packer.build_tokens(brand, accent)

    # ---- 圆角 token（可选）：风格预设 + 逐项覆盖
    # MIUI 主题不暴露数值圆角（theme_values.xml 只映射 drawable 名），
    # 所以用"风格预设"让包作者显式选择，而不是从美术里瞎猜。
    RADIUS_PROFILES = {
        "default": {"radius.sm": 8.0, "radius.md": 12.0, "radius.lg": 16.0, "radius.sheet": 24.0},
        "soft": {"radius.sm": 12.0, "radius.md": 16.0, "radius.lg": 22.0, "radius.sheet": 28.0},
        "round": {"radius.sm": 16.0, "radius.md": 22.0, "radius.lg": 28.0, "radius.sheet": 36.0},
        "sharp": {"radius.sm": 6.0, "radius.md": 8.0, "radius.lg": 10.0, "radius.sheet": 16.0},
    }
    radius_tokens = dict(RADIUS_PROFILES.get(args.radius_profile or "", {}))
    for short, value in (("sm", args.radius_sm), ("md", args.radius_md),
                         ("lg", args.radius_lg), ("sheet", args.radius_sheet)):
        if value is not None:
            radius_tokens["radius." + short] = float(value)
    if radius_tokens:
        for mode in ("light", "dark"):
            tokens[mode].update(radius_tokens)
        radius_problems = packer.validate_tokens(tokens)
        if radius_problems:
            raise SystemExit("圆角取值非法：" + "；".join(radius_problems))
        print("radius tokens:", radius_tokens)
    warnings = list(token_report.get("warnings", []))
    print(json.dumps(token_report, ensure_ascii=False, indent=2))

    # ---- 壁纸
    walls = miui.wallpaper_sources(theme)
    assets: list[packer.PackAsset] = []
    wall_rows = []
    if "portrait" in walls:
        p = img.pack_wallpaper(walls["portrait"], img.PORTRAIT_SIZE, 85)
        assets.append(packer.PackAsset("assets/wallpaper_portrait.jpg", p.data))
        wall_rows.append(["portrait 1080x2400", _fmt_mb(len(walls["portrait"])), _fmt_mb(p.bytes), f"q85 {p.width}x{p.height}"])
        l = img.pack_wallpaper(walls["portrait"], img.LANDSCAPE_SIZE, 85)
        assets.append(packer.PackAsset("assets/wallpaper_landscape.jpg", l.data))
        wall_rows.append(["landscape 2400x1080", "—", _fmt_mb(l.bytes), f"q85 {l.width}x{l.height}"])
        dom = img.dominant_colors(walls["portrait"], 3)
    else:
        dom = []
    if "lock" in walls:
        lk = img.pack_wallpaper(walls["lock"], img.PORTRAIT_SIZE, 85)
        assets.append(packer.PackAsset("assets/wallpaper_lock.jpg", lk.data))
        wall_rows.append(["lock 1080x2400", _fmt_mb(len(walls["lock"])), _fmt_mb(lk.bytes), "q85"])

    # ---- 预览
    previews: list[packer.PackAsset] = []
    prev_rows = []
    for stem, raw in miui.preview_sources(theme).items():
        p = img.pack_preview(raw, 82)
        name = f"assets/preview_{stem.replace('preview_', '')}.jpg"
        previews.append(packer.PackAsset(name, p.data))
        prev_rows.append([name, _fmt_mb(len(raw)), _fmt_mb(p.bytes), f"{p.width}x{p.height}"])
        if len(previews) >= 6:
            break

    # ---- 字体
    capabilities = {"font": False, "icons": False, "radius": True}
    font_rows = []
    font_meta = {}
    if args.font:
        charset, meta = fontsub.build_charset(args.lib)
        family = FONT_FAMILY.format(id=args.pack_id)
        sub = fontsub.subset_font(args.font, charset, family, 400)
        assets.append(packer.PackAsset(f"assets/fonts/{family}.ttf", sub.data))
        capabilities["font"] = True
        font_meta = {
            "family": family,
            "weight": 400,
            "chars": sub.char_count,
            "source_bytes": sub.source_bytes,
            "pack_bytes": len(sub.data),
            **{f"charset_{k}": v for k, v in meta.items()},
        }
        font_rows.append([
            family,
            str(sub.char_count),
            _fmt_mb(sub.source_bytes),
            _fmt_mb(len(sub.data)),
            f"{(1 - len(sub.data) / sub.source_bytes) * 100:.1f}%",
        ])

    # ---- 角色插画（空态用；透明底）
    mascot_rows = []
    if args.with_mascot and getattr(args, "mascot_card", False):
        raw_card = miui.read_asset(
            theme,
            "com.miui.contentextension:res/drawable-xxhdpi/card_bg_content.png",
            "com.miui.contentextension:res/drawable-xhdpi/card_bg_content.png",
        )
        if raw_card:
            packed = img.pack_avatar(raw_card, center=(0.42, 0.42), crop_ratio=0.58)
            assets.append(packer.PackAsset("assets/mascot_idle.png", packed.data))
            capabilities["mascot"] = True
            mascot_rows.append([
                "assets/mascot_idle.png",
                "卡片大图裁头像（高清）",
                f"{packed.width}x{packed.height}",
                _fmt_mb(len(raw_card)),
                _fmt_mb(packed.bytes),
            ])
            warnings.append("角色取自 card_bg_content.png（2034x1720 大图），非 AOD 帧")
            raw_idle = None
        else:
            raw_idle = None
            warnings.append("未找到 card_bg_content.png，回退 AOD 帧")
    if args.with_mascot and not mascot_rows:
        # AOD 帧是「全彩角色 + 纯黑底」，抠图最干净；
        # systemui 的大图磁贴底色与角色同色系，抠完只剩线稿，不可用。
        raw_idle = miui.read_asset(
            theme,
            'aod:content/img/img_nuom_06.png',
            'aod:content/img/img_nuom_12.png',
            'aod:content/img/img_nuom_00.png',
        )
        if raw_idle:
            # AOD 帧固定是全彩角色 + 纯黑底，明确指定黑底；
            # 不要让自动判底色去猜（椎名真由理那套被猜成白底，脸被抠穿）
            packed = img.pack_mascot(raw_idle, force_bg=(0, 0, 0))
            # 深色头发的角色会被黑底"吃掉"，破洞率过高时改用壁纸裁头像
            if img.mascot_hole_ratio(packed) > 0.35:
                # 只用**竖屏壁纸**：横屏构图不同，按比例裁会裁到帽子/天空
                wall = next(
                    (a.data for a in assets if a.path == 'assets/wallpaper_portrait.jpg'),
                    None,
                )
                if wall:
                    packed = img.pack_avatar(wall)
                    warnings.append('角色为深色系，已改用壁纸裁圆形头像（抠图会破洞）')
            assets.append(packer.PackAsset('assets/mascot_idle.png', packed.data))
            capabilities['mascot'] = True
            mascot_rows.append([
                'assets/mascot_idle.png',
                '困倦坐姿（抠底）',
                f'{packed.width}x{packed.height}',
                _fmt_mb(len(raw_idle)),
                _fmt_mb(packed.bytes),
            ])
            # 顺带留一张实色底的横幅图（详情页备用，不进白名单校验）
            raw_sleep = miui.read_asset(
                theme,
                'com.android.systemui:res/drawable-nxhdpi/ic_qs_big_tile_bg_0.png',
            )
            if raw_sleep:
                banner = img.pack_wallpaper(raw_sleep, (1600, 762), 86)
                assets.append(packer.PackAsset('assets/mascot_banner.jpg', banner.data))
                mascot_rows.append([
                    'assets/mascot_banner.jpg',
                    '卡片横幅（实色底）',
                    f'{banner.width}x{banner.height}',
                    _fmt_mb(len(raw_sleep)),
                    _fmt_mb(banner.bytes),
                ])
        else:
            warnings.append('未找到角色立绘（ic_qs_big_tile_bg_*），本包不含空态插画')

    # ---- 卡片纹理 / 详情横幅（可选）
    texture_rows = []
    # 页面纹理已下线：card_texture 是「带角色的会话背景图」，整页叠加像虚影，
    # 客户端也不再读取。保留 pack_texture() 供以后做可平铺噪点纹理时复用。

    raw_banner = miui.read_asset(
        theme,
        'com.android.systemui:res/drawable-nxhdpi/ic_qs_big_tile_bg_0.png',
    )
    if raw_banner:
        ban = img.pack_banner(raw_banner)
        assets.append(packer.PackAsset('assets/banner_detail.jpg', ban.data))
        texture_rows.append(['assets/banner_detail.jpg', '磁贴大图（横幅）',
                             f'{ban.width}x{ban.height}', _fmt_mb(len(raw_banner)), _fmt_mb(ban.bytes)])

    # ---- 状态插图（加载/空态/错误态，可选）
    raw_state = miui.read_asset(
        theme,
        'com.android.updater:res/drawable-xxhdpi/v12.5_head_image.png',
        'com.android.updater:res/drawable-xhdpi/v12.5_head_image.png',
    )
    if raw_state:
        st = img.pack_texture(raw_state, width=512, quality=82)
        assets.append(packer.PackAsset('assets/state_art.jpg', st.data))
        capabilities['stateArt'] = True
        texture_rows.append(['assets/state_art.jpg', '更新页头图（状态插图）',
                             f'{st.width}x{st.height}', _fmt_mb(len(raw_state)), _fmt_mb(st.bytes)])

    # ---- 组装
    draft = packer.PackDraft(
        pack_id=args.pack_id,
        name=args.name,
        version=args.version,
        min_app_version=args.min_app_version,
        source=args.source,
        author=args.author,
        license=args.license,
        license_text=args.license_text,
        tokens=tokens,
        assets=assets,
        previews=previews,
        capabilities=capabilities,
        notes={
            "convertedFrom": theme.name,
            "converter": "tools/theme_pack_converter",
            "brandCandidates": [
                {"color": c["color"], "global": c["global_count"], "semantic": c["semantic_hits"]}
                for c in candidates[:6]
            ],
            "wallpaperDominant": dom,
            "font": font_meta or None,
            "warnings": warnings or None,
        },
    )

    out_pack = out_dir / f"{args.pack_id}{packer.PACK_SUFFIX}"
    manifest = packer.write_pack(draft, out_pack)
    verified = packer.verify_pack(out_pack)

    # ---- 报告
    lines: list[str] = []
    lines.append(f"# 主题包转换报告 · {args.name} (`{args.pack_id}`)\n")
    lines.append(f"- 源目录：`{theme}`")
    lines.append(f"- 产物：`{out_pack}`（{_fmt_mb(out_pack.stat().st_size)}）")
    lines.append(f"- 校验：{'通过' if not verified['problems'] else '失败 → ' + '; '.join(verified['problems'])}\n")

    lines.append("## 1. 扫描到的模块\n")
    rows = [[n, i.theme_value_files, i.color_count] for n, i in sorted(scan.modules.items(), key=lambda kv: -kv[1].color_count)]
    lines.append(_table(rows, ["module", "theme_values.xml", "colors"]))
    lines.append(f"\nicons 模块里的图标 PNG：{miui.icon_codepoints(theme)} 个（Android 包名图标，不进入 App）\n")

    lines.append("## 2. 主色候选（按语义命中 + 全局权重排序）\n")
    rows = [[c["color"], c["global_count"], c["semantic_hits"], c["modules"], ", ".join(c["sample_names"][:2])] for c in candidates[:8]]
    lines.append(_table(rows, ["color", "全局出现", "语义名命中", "模块数", "样例资源名"]))
    lines.append("")
    lines.append("选定与调整：\n")
    lines.append(f"- 品牌主色（light）：`{token_report['brand_light']}`（输入 `{token_report['brand_input']}`，"
                 f"{'经过对比度修正' if token_report['brand_light_adjusted'] else '原样采用'}，"
                 f"对浅底对比度 {token_report['contrast_light_bg']}:1）")
    lines.append(f"- 品牌主色（dark）：`{token_report['brand_dark']}`（对深底对比度 {token_report['contrast_dark_bg']}:1）")
    if "accent_input" in token_report:
        lines.append(f"- 次强调色：`{token_report.get('accent_input')}` → light `{tokens['light'].get('accent.secondary')}` / dark `{tokens['dark'].get('accent.secondary')}`")
    if dom:
        lines.append(f"- 壁纸主色（参考）：{', '.join('`' + d + '`' for d in dom)}")
    if warnings:
        lines.append("")
        lines.append("**警告**：")
        for w in warnings:
            lines.append(f"- {w}")
    lines.append("")

    lines.append("## 3. 壁纸与预览（压缩前后）\n")
    lines.append(_table(wall_rows, ["用途", "原始", "压缩后", "说明"]))
    lines.append("")
    lines.append(_table(prev_rows, ["预览", "原始", "压缩后", "尺寸"]))
    lines.append("")

    lines.append("## 4. 角色插画（空态）\n")
    if mascot_rows:
        lines.append(_table(mascot_rows, ["资产", "来源", "尺寸", "原始", "转换后"]))
        lines.append("")
        lines.append("- `mascot_idle.png`：按底色键控抠图 + 羽化 + 裁到内容外接框 + 512 方形，透明底")
        lines.append("- 没有该资产时，App 空态仍显示原来的图标（零行为变化）")
    else:
        lines.append("- 本包未包含角色插画。")
    lines.append("")

    lines.append("## 5. 字体子集\n")
    if font_rows:
        lines.append(_table(font_rows, ["family", "字符数", "原始", "子集后", "压缩率"]))
        lines.append("")
        lines.append(f"- 字符集来源：源码中文 {font_meta['charset_from_code']} 个 + GB2312 一级 {font_meta['charset_gb2312_level1']} 个 + ASCII/标点，合计 {font_meta['charset_total']} 个")
        lines.append(f"- 运行时用 `FontLoader('{font_meta['family']}')` 加载；失败回落 `NotoSansCJKsc`")
    else:
        lines.append("- 未指定 `--font`，本包不含字体。")
    lines.append("")

    lines.append("## 6. tokens.json（实际写入）\n")
    lines.append("```json")
    lines.append(json.dumps(tokens, ensure_ascii=False, indent=2))
    lines.append("```\n")
    lines.append("> 只写入从主题中确证抽到的键；`bg/surface/text/border` 交给 App 默认值回落，避免猜色破坏可读性。\n")

    lines.append("## 7. manifest 摘要\n")
    lines.append("```json")
    summary = {k: v for k, v in manifest.items() if k not in ("assets", "preview", "notes")}
    lines.append(json.dumps(summary, ensure_ascii=False, indent=2))
    lines.append("```")
    lines.append(f"\n资产 {len(manifest['assets'])} 个 / 预览 {len(manifest['preview'])} 个，"
                 f"manifest 计体积 {_fmt_mb(manifest['bytes'])}，包文件 {_fmt_mb(out_pack.stat().st_size)}。")

    report_path = out_dir / "pack-report.md"
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\npack:   {out_pack}")
    print(f"report: {report_path}")
    print(f"verify: {'OK' if not verified['problems'] else verified['problems']}")
    return 0 if not verified["problems"] else 1


# --------------------------------------------------------------------------- build-all
def cmd_build_all(args) -> int:
    """批量转换：`--themes <父目录>` 下每个主题目录各出一个包，并写 catalog.json 给 App 主题模块用。"""
    parent = Path(args.themes)
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    id_map = {}
    if args.id_map:
        id_map = json.loads(Path(args.id_map).read_text(encoding="utf-8"))

    dirs = [p for p in sorted(parent.iterdir()) if miui.looks_like_theme(p)] if parent.is_dir() else []
    if not dirs:
        print(f"!! {parent} 下没有识别到主题目录（需要 description.xml + ≥3 个模块）", file=sys.stderr)
        return 2
    print(f"发现 {len(dirs)} 个主题目录")

    catalog: list[dict] = []
    for index, theme_dir in enumerate(dirs, start=1):
        desc = miui.read_description(theme_dir)
        pack_id = id_map.get(theme_dir.name) or f"{args.id_prefix}-{index:02d}"
        name = desc.get("title") or theme_dir.name
        print(f"\n--- [{index}/{len(dirs)}] {theme_dir.name} → {pack_id} ({name})")
        ns = argparse.Namespace(**vars(args))
        ns.theme = str(theme_dir)
        ns.pack_id = pack_id
        ns.name = name
        ns.author = desc.get("author") or desc.get("designer") or args.author
        rc = cmd_build(ns)
        if rc != 0:
            print(f"!! {theme_dir.name} 构建失败，跳过")
            continue
        pack_path = out_dir / f"{pack_id}{packer.PACK_SUFFIX}"
        with __import__("zipfile").ZipFile(pack_path) as zf:
            manifest = json.loads(zf.read("manifest.json").decode("utf-8"))
            tokens = json.loads(zf.read("tokens.json").decode("utf-8"))
        catalog.append(
            {
                "id": manifest["id"],
                "name": manifest["name"],
                "version": manifest["version"],
                "minAppVersion": manifest["minAppVersion"],
                "bytes": pack_path.stat().st_size,
                "sha256": __import__("hashlib").sha256(pack_path.read_bytes()).hexdigest(),
                "file": pack_path.name,
                "brand": tokens.get("light", {}).get("brand.primary"),
                "brandDark": tokens.get("dark", {}).get("brand.primary"),
                "capabilities": manifest.get("capabilities", {}),
                "preview": [p["path"] for p in manifest.get("preview", [])],
                "sourceTheme": theme_dir.name,
                "themeVersion": desc.get("version"),
                "miuiVersion": desc.get("miuiVersion"),
            }
        )

    catalog_path = out_dir / "catalog.json"
    payload = {"schema": 1, "generatedBy": "tools/theme_pack_converter", "packs": catalog}
    catalog_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\ncatalog: {catalog_path}  （{len(catalog)} 个包）")
    for item in catalog:
        print(f"  {item['id']:16s} {item['name'][:20]:22s} {item['bytes'] / 1024 / 1024:5.2f} MB  {item['brand']}")
    return 0


# --------------------------------------------------------------------------- verify / icons
def cmd_verify(args) -> int:
    result = packer.verify_pack(args.pack)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not result["problems"] else 1


def cmd_icons(args) -> int:
    """统计 App 实际用到的 Material 图标数量（P4 换图标时用）。"""
    root = Path(args.flutter_root) if args.flutter_root else None
    if root is None:
        print("需要 --flutter-root <Flutter SDK 根目录>（icons.dart 在 packages/flutter/lib/src/material/）")
        return 2
    icons_dart = root / "packages/flutter/lib/src/material/icons.dart"
    if not icons_dart.is_file():
        print(f"找不到 {icons_dart}")
        return 2
    import re
    text = icons_dart.read_text(encoding="utf-8", errors="ignore")
    entries = re.findall(r"static const IconData (\w+) = IconData\((0x[0-9a-fA-F]+)", text)
    print(f"Flutter 提供的 IconData: {len(entries)} 个")
    lib = Path(args.lib)
    used: set[str] = set()
    if lib.is_dir():
        for path in lib.rglob("*.dart"):
            t = path.read_text(encoding="utf-8", errors="ignore")
            used.update(re.findall(r"\bIcons\.(\w+)", t))
    known = {name for name, _ in entries}
    print(f"App 实际引用: {len(used)} 个（其中未在 SDK 中找到: {len(used - known)}）")
    if used - known:
        print("  " + ", ".join(sorted(used - known)[:20]))
    return 0


# --------------------------------------------------------------------------- main
def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="theme_pack_converter", description="MIUI 主题包 → SYLUlive .syltheme")
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("inspect", help="只读扫描：模块、颜色候选")
    pi.add_argument("theme")
    pi.set_defaults(func=cmd_inspect)

    pb = sub.add_parser("build", help="构建 .syltheme")
    pb.add_argument("theme")
    pb.add_argument("-o", "--out", required=True)
    pb.add_argument("--id", dest="pack_id", default="shenli-joy13")
    pb.add_argument("--name", default="深理·鲸")
    pb.add_argument("--version", default="1.0.0")
    pb.add_argument("--min-app-version", default=DEFAULT_MIN_APP)
    pb.add_argument("--source", default="imported", choices=("builtin", "imported", "remote"))
    pb.add_argument("--author", default="SYLUlive")
    pb.add_argument("--license", default="OFL-1.1")
    pb.add_argument("--license-text", default="字体与素材授权见包内 license/ 目录")
    pb.add_argument("--brand", help="主色 #AARRGGBB；省略则用扫描第一名候选")
    pb.add_argument("--accent", help="次强调色")
    pb.add_argument("--font", help="要子集化的字体文件（TTF/OTF）")
    pb.add_argument("--lib", help="client/lib 目录，用于抽取字符集")
    pb.add_argument("--mascot-card", dest="mascot_card", action="store_true",
                    help="从 com.miui.contentextension 的 card_bg_content.png（大图）裁角色头像，画质优于 AOD 帧")
    pb.add_argument("--radius-profile", choices=("default", "soft", "round", "sharp"),
                    help="圆角风格预设：default(8/12/16/24) soft(12/16/22/28) round(16/22/28/36) sharp(6/8/10/16)")
    pb.add_argument("--radius-sm", type=float)
    pb.add_argument("--radius-md", type=float)
    pb.add_argument("--radius-lg", type=float)
    pb.add_argument("--radius-sheet", type=float)
    pb.add_argument("--with-mascot", dest="with_mascot", action="store_true", default=True,
                    help="抽取角色插画做空态图（默认开启）")
    pb.add_argument("--no-mascot", dest="with_mascot", action="store_false",
                    help="不抽取角色插画")
    pb.set_defaults(func=cmd_build)

    pv = sub.add_parser("verify", help="校验已有包")
    pv.add_argument("pack")
    pv.set_defaults(func=cmd_verify)

    pa = sub.add_parser("build-all", help="批量转换并生成 catalog.json")
    pa.add_argument("--themes", required=True, help="包含多个主题目录的父目录")
    pa.add_argument("-o", "--out", required=True)
    pa.add_argument("--id-prefix", default="pack")
    pa.add_argument("--id-map", help="JSON：{目录名: 包 id}")
    pa.add_argument("--version", default="1.0.0")
    pa.add_argument("--min-app-version", default=DEFAULT_MIN_APP)
    pa.add_argument("--source", default="imported", choices=("builtin", "imported", "remote"))
    pa.add_argument("--author", default="SYLUlive")
    pa.add_argument("--license", default="OFL-1.1")
    pa.add_argument("--license-text", default="字体与素材授权见包内 license/ 目录")
    pa.add_argument("--brand", help="强制统一主色（默认每个包各取自己的第一名候选）")
    pa.add_argument("--accent")
    pa.add_argument("--font")
    pa.add_argument("--lib")
    pa.add_argument("--with-mascot", dest="with_mascot", action="store_true", default=True)
    pa.add_argument("--no-mascot", dest="with_mascot", action="store_false")
    pa.set_defaults(func=cmd_build_all)

    pc = sub.add_parser("icons", help="统计 App 用到的 Material 图标")
    pc.add_argument("--flutter-root")
    pc.add_argument("--lib", default="../../client/lib")
    pc.set_defaults(func=cmd_icons)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
