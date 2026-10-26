import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_palette.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack.dart';

/// 调色板解析契约：缺 token 逐条回落、非法条目静默丢弃、深色可派生。

void main() {
  group('ThemePalette.fromTokens', () {
    test('解析颜色 / 圆角 / 玻璃', () {
      final palette = ThemePalette.fromTokens({
        'brand.primary': '#FF7B8BCF',
        'tag.bg': '#E9E8EE',
        'radius.md': 14.0,
          });
      expect(palette.brandPrimary, const Color(0xFF7B8BCF));
      expect(palette.tagBackground, const Color(0xFFE9E8EE));
      expect(palette.radius('radius.md'), 14.0);
      });

    test('#RRGGBB 自动补 alpha', () {
      final palette = ThemePalette.fromTokens({'brand.primary': '#7B8BCF'});
      expect(palette.brandPrimary, const Color(0xFF7B8BCF));
      expect(palette.brandPrimary!.a, 1.0);
    });

    test('未声明的键返回 null（逐条回落）', () {
      final palette = ThemePalette.fromTokens({'brand.primary': '#FF7B8BCF'});
      expect(palette.accentSecondary, isNull);
      expect(palette.background, isNull);
      expect(palette.radius('radius.lg'), isNull);
      });

    test('非法条目被静默丢弃，不影响其它条目', () {
      final palette = ThemePalette.fromTokens({
        'brand.primary': 'not-a-color',
        'danger': '#FFFF0000', // 禁改项
        'spacing.md': 12.0, // 禁改项
        'radius.md': 999.0, // 超范围
        'tag.bg': '#FFE9E8EE', // 合法
      });
      expect(palette.brandPrimary, isNull);
      expect(palette.tagBackground, const Color(0xFFE9E8EE));
      expect(palette.colors.containsKey('danger'), isFalse);
      expect(palette.radii.containsKey('radius.md'), isFalse);
    });

    test('非 Map 输入得到空板', () {
      expect(ThemePalette.fromTokens(null).isEmpty, isTrue);
      expect(ThemePalette.fromTokens('nope').isEmpty, isTrue);
      expect(ThemePalette.empty.isEmpty, isTrue);
    });

    test('parseHexColor 容错', () {
      expect(ThemePalette.parseHexColor('#FF0000'), const Color(0xFFFF0000));
      expect(ThemePalette.parseHexColor('FF0000'), isNull);
      expect(ThemePalette.parseHexColor('#GGGGGG'), isNull);
      expect(ThemePalette.parseHexColor('#12345'), isNull);
      expect(ThemePalette.parseHexColor(null), isNull);
    });
  });

  group('深色派生', () {
    test('品牌色变亮、背景变暗、圆角保留', () {
      final light = ThemePalette.fromTokens({
        'brand.primary': '#FF2E3A6E', // 深蓝
        'bg.primary': '#FFF0F0F0', // 浅灰
        'radius.md': 14.0,
      });
      final dark = ThemePack.deriveDark(light);

      final lightBrand = HSLColor.fromColor(light.brandPrimary!).lightness;
      final darkBrand = HSLColor.fromColor(dark.brandPrimary!).lightness;
      expect(darkBrand, greaterThan(lightBrand), reason: '深色下品牌色应提亮');

      final lightBg = HSLColor.fromColor(light.background!).lightness;
      final darkBg = HSLColor.fromColor(dark.background!).lightness;
      expect(darkBg, lessThan(lightBg), reason: '深色下背景应压暗');

      expect(dark.radius('radius.md'), 14.0, reason: '圆角与明暗无关');
    });

    test('空板派生仍是空板', () {
      expect(ThemePack.deriveDark(ThemePalette.empty).isEmpty, isTrue);
    });
  });

  group('ThemePack.fromParts', () {
    Map<String, Object?> manifest() => {
          'schema': 1,
          'id': 'p1',
          'name': '测试',
          'version': '1.0.0',
          'minAppVersion': '1.7.6',
          'source': 'imported',
          'license': 'OFL-1.1',
          'assets': [
            {'path': 'assets/a.jpg', 'sha256': 'a' * 64, 'bytes': 10},
          ],
          'capabilities': {'mascot': true},
        };

    test('缺 dark 时自动派生', () {
      final pack = ThemePack.fromParts(
        manifestJson: manifest(),
        tokensJson: {
          'light': {'brand.primary': '#FF7B8BCF'},
        },
        rootPath: '/tmp/p1',
        isBuiltin: false,
      )!;
      expect(pack.light.brandPrimary, isNotNull);
      expect(pack.dark.brandPrimary, isNotNull);
    });

    test('有 dark 时直接使用', () {
      final pack = ThemePack.fromParts(
        manifestJson: manifest(),
        tokensJson: {
          'light': {'brand.primary': '#FF7B8BCF'},
          'dark': {'brand.primary': '#FF8E9BD6'},
        },
        rootPath: '/tmp/p1',
        isBuiltin: false,
      )!;
      expect(pack.dark.brandPrimary, const Color(0xFF8E9BD6));
    });

    test('assetPath / hasAsset', () {
      final pack = ThemePack.fromParts(
        manifestJson: manifest(),
        tokensJson: {
          'light': <String, Object?>{},
        },
        rootPath: '/tmp/p1',
        isBuiltin: false,
      )!;
      expect(pack.assetPath('assets/a.jpg'), '/tmp/p1/assets/a.jpg');
      expect(pack.hasAsset('assets/a.jpg'), isTrue);
      expect(pack.hasAsset('assets/missing.png'), isFalse);
      expect(pack.manifest.capability('mascot'), isTrue);
      expect(pack.manifest.capability('font'), isFalse);
    });
  });
}
