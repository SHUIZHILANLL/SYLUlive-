"""字体子集化：从 App 源码抽字符集，用 fontTools 生成子集，控制包体积。

现行 App 只带 NotoSansCJKsc-Regular.otf（15.7 MB 单字重）。整包塞进主题包不可接受，
所以主题包字体必须按「App 实际用到的字符 + GB2312 一级常用字」子集化。
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass
from pathlib import Path

from fontTools import subset as ftsubset

CJK_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
# 中文排版常用标点（全角、CJK 符号、通用标点）
CJK_PUNCT = (
    "　、。〈〉《》「」『』【】〔〕〖〗！＂＃＄％＆＇（）＊＋，－．／０１２３４５６７８９"
    "：；＜＝＞？＠［＼］＾＿｀｛｜｝～￥…—·“”‘’°±×÷≈≠≤≥∞√∫"
)
ASCII_PRINTABLE = "".join(chr(c) for c in range(0x20, 0x7F))


@dataclass
class SubsetResult:
    family: str
    weight: int
    data: bytes
    char_count: int
    source_bytes: int

    @property
    def bytes(self) -> int:
        return len(self.data)


def gb2312_level1() -> str:
    """GB2312 一级汉字（3755 个常用字），纯 stdlib 枚举，无需外部字表。"""
    chars: list[str] = []
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.append(bytes((hi, lo)).decode("gb2312"))
            except UnicodeDecodeError:
                continue
    return "".join(chars)


def charset_from_sources(lib_dir: str | Path) -> set[str]:
    """扫描 Dart 源码，收集所有中文字符。"""
    found: set[str] = set()
    lib = Path(lib_dir)
    if not lib.is_dir():
        return found
    for path in lib.rglob("*.dart"):
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        found.update(CJK_RE.findall(text))
    return found


def build_charset(lib_dir: str | Path | None) -> tuple[str, dict]:
    code_chars = charset_from_sources(lib_dir) if lib_dir else set()
    merged = set(ASCII_PRINTABLE) | set(CJK_PUNCT) | set(gb2312_level1()) | code_chars
    meta = {
        "from_code": len(code_chars),
        "gb2312_level1": len(gb2312_level1()),
        "total": len(merged),
    }
    return "".join(sorted(merged)), meta


def subset_font(
    font_path: str | Path,
    charset: str,
    family: str,
    weight: int = 400,
    flavor: str | None = None,
) -> SubsetResult:
    """生成子集字体。flavor 传 'woff2' 可再压一层（Flutter 不支持，仅用于对比报告）。"""
    font_path = Path(font_path)
    opts = ftsubset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.name_legacy = True
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]
    opts.flavor = flavor

    font = ftsubset.load_font(str(font_path), opts)
    subsetter = ftsubset.Subsetter(options=opts)
    subsetter.populate(text=charset)
    subsetter.subset(font)

    buf = io.BytesIO()
    ftsubset.save_font(font, buf, opts)
    return SubsetResult(
        family=family,
        weight=weight,
        data=buf.getvalue(),
        char_count=len(charset),
        source_bytes=font_path.stat().st_size,
    )
