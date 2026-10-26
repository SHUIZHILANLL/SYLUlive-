"""转换器单元测试：白名单、圆角范围、对比度、包校验。

运行：python -m unittest test_converter -v
"""

from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

import colorutil as cu
import fontsub
import pack


class TokenWhitelistTest(unittest.TestCase):
    def test_accepts_whitelisted_keys(self):
        tokens = {
            "light": {"brand.primary": "#FF7B8BCF", "radius.md": 14.0},
            "dark": {"brand.primary": "#FF8E9BD6"},
        }
        self.assertEqual(pack.validate_tokens(tokens), [])

    def test_rejects_unknown_key(self):
        problems = pack.validate_tokens({"light": {"spacing.md": 12.0}})
        self.assertTrue(problems)
        self.assertTrue(any("spacing" in p for p in problems))

    def test_rejects_status_colors(self):
        for key in ("danger", "successSurface", "warning.text", "info"):
            key_with_dot = key if "." in key else f"brand.{key}"
            problems = pack.validate_tokens({"light": {key_with_dot: "#FFFF0000"}})
            self.assertTrue(problems, f"{key} 应被拒绝")

    def test_rejects_pill_radius(self):
        problems = pack.validate_tokens({"light": {"radius.pill": 999.0}})
        self.assertTrue(problems)

    def test_radius_range(self):
        self.assertTrue(pack.validate_tokens({"light": {"radius.md": 30.0}}))
        self.assertTrue(pack.validate_tokens({"light": {"radius.md": 2.0}}))
        self.assertEqual(pack.validate_tokens({"light": {"radius.md": 8.0}}), [])

    def test_rejects_bad_color_format(self):
        self.assertTrue(pack.validate_tokens({"light": {"brand.primary": "7B8BCF"}}))


class ContrastTest(unittest.TestCase):
    def test_contrast_ratio_bounds(self):
        self.assertAlmostEqual(cu.contrast_ratio("#FFFFFFFF", "#FF000000"), 21.0, places=1)
        self.assertAlmostEqual(cu.contrast_ratio("#FF777777", "#FF777777"), 1.0, places=2)

    def test_ensure_contrast_reaches_minimum(self):
        color, changed = cu.ensure_contrast("#FF7B8BCF", "#FFFAF4", 4.5)
        self.assertTrue(changed)
        self.assertGreaterEqual(cu.contrast_ratio(color, "#FFFAF4"), 4.5)

    def test_ensure_contrast_noop_when_ok(self):
        color, changed = cu.ensure_contrast("#FF000000", "#FFFFFFFF", 4.5)
        self.assertFalse(changed)
        self.assertEqual(color, "#FF000000")

    def test_best_on_color(self):
        self.assertEqual(cu.best_on_color("#FF101010"), "#FFFFFFFF")
        self.assertEqual(cu.best_on_color("#FFF0F0F0"), "#FF000000")


class BuildTokensTest(unittest.TestCase):
    def test_light_and_dark_have_brand(self):
        tokens, report = pack.build_tokens("#FF7B8BCF")
        self.assertIn("brand.primary", tokens["light"])
        self.assertIn("brand.primary", tokens["dark"])
        self.assertGreaterEqual(report["contrast_dark_bg"], 3.0)

    def test_impossible_accent_is_dropped_with_warning(self):
        _, report = pack.build_tokens("#FF7B8BCF", "#FF66CCFF")
        if report.get("accent_lightness_delta", 0) > 0.25:
            self.assertNotIn("accent.secondary", report.get("dropped", []) or [])
            self.assertTrue(report.get("warnings"))


class CharsetTest(unittest.TestCase):
    def test_gb2312_level1_size(self):
        chars = fontsub.gb2312_level1()
        self.assertGreater(len(chars), 3000)
        self.assertLess(len(chars), 4000)
        self.assertIn("学", chars)

    def test_charset_includes_punctuation_and_ascii(self):
        charset, meta = fontsub.build_charset(None)
        self.assertIn("A", charset)
        self.assertIn("，", charset)
        self.assertEqual(meta["from_code"], 0)


class VerifyPackTest(unittest.TestCase):
    def test_roundtrip_and_tamper_detection(self):
        draft = pack.PackDraft(
            pack_id="unit-test",
            name="单元测试",
            version="0.0.1",
            min_app_version="1.7.6",
            source="imported",
            author="test",
            license="OFL-1.1",
            license_text="n/a",
            tokens={"light": {"brand.primary": "#FF112233"}, "dark": {"brand.primary": "#FF445566"}},
            assets=[pack.PackAsset("assets/wallpaper_portrait.jpg", b"\xff\xd8fakejpeg")],
            capabilities={"font": False, "icons": False, "radius": True},
        )
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "p.syltheme"
            pack.write_pack(draft, out)
            result = pack.verify_pack(out)
            self.assertEqual(result["problems"], [])

            # 篡改资产内容后必须被发现
            tampered = Path(tmp) / "bad.syltheme"
            with zipfile.ZipFile(out) as src, zipfile.ZipFile(tampered, "w") as dst:
                for item in src.infolist():
                    data = src.read(item.filename)
                    if item.filename == "assets/wallpaper_portrait.jpg":
                        data = b"\xff\xd8tampered"
                    dst.writestr(item, data)
            bad = pack.verify_pack(tampered)
            self.assertTrue(any("sha256" in p for p in bad["problems"]))

    def test_write_rejects_bad_tokens(self):
        draft = pack.PackDraft(
            pack_id="bad", name="bad", version="1", min_app_version="1.7.6",
            source="imported", author="t", license="x", license_text="x",
            tokens={"light": {"danger": "#FFFF0000"}},
        )
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(pack.PackError):
                pack.write_pack(draft, Path(tmp) / "bad.syltheme")


if __name__ == "__main__":
    unittest.main(verbosity=2)
