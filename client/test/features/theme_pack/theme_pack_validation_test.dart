import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack_manifest.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack_tokens.dart';

/// 主题包契约校验：白名单、禁改项、版本门槛、资产安全、sha256 格式。
///
/// 这些规则必须与 `tools/theme_pack_converter/pack.py` 完全一致，
/// 两边任一不通过都不允许安装。

Map<String, Object?> validManifest({
  Object? schema = 1,
  String id = 'shenli-joy13',
  String name = '深理·鲸',
  String version = '1.0.0',
  String minAppVersion = '1.7.6',
  String source = 'imported',
  String license = 'OFL-1.1',
  List<Map<String, Object?>>? assets,
  Map<String, Object?>? capabilities,
  int? bytes,
}) {
  final defaultAssets = assets ??
      [
        {
          'path': 'assets/wallpaper_portrait.jpg',
          'sha256': 'a' * 64,
          'bytes': 100,
        },
      ];
  return {
    'schema': schema,
    'id': id,
    'name': name,
    'version': version,
    'minAppVersion': minAppVersion,
    'source': source,
    'author': 'test',
    'license': license,
    'licenseText': 'n/a',
    'bytes': bytes ?? defaultAssets.fold<int>(0, (a, e) => a + (e['bytes'] as int)),
    'assets': defaultAssets,
    'preview': <Map<String, Object?>>[],
    'capabilities': capabilities ?? {'mascot': true},
  };
}

Map<String, Object?> validTokens() => {
      'light': {
        'brand.primary': '#FF7B8BCF',
        'tag.bg': '#FFE9E8EE',
        'tag.text': '#FF475DBC',
        'radius.md': 14.0,
      },
      'dark': {'brand.primary': '#FF8E9BD6'},
    };

void main() {
  group('tokens 白名单', () {
    test('合法 tokens 通过', () {
      expect(ThemePackTokens.validate(Map<String, dynamic>.from(validTokens())), isEmpty);
    });

    test('状态语义色不可覆盖', () {
      for (final key in ['danger', 'success', 'warning', 'info', 'danger.surface']) {
        final problems = ThemePackTokens.validate({
          'light': {key: '#FFFF0000'},
        });
        expect(problems, isNotEmpty, reason: '$key 应被拒绝');
      }
    });

    test('间距不可覆盖', () {
      final problems = ThemePackTokens.validate({
        'light': {'spacing.md': 12.0},
      });
      expect(problems, isNotEmpty);
      expect(problems.first, contains('spacing'));
    });

    test('radius.pill 不可覆盖', () {
      final problems = ThemePackTokens.validate({
        'light': {'radius.pill': 999.0},
      });
      expect(problems, isNotEmpty);
    });

    test('未知 key 被拒绝', () {
      final problems = ThemePackTokens.validate({
        'light': {'brand.tertiary': '#FF112233'},
      });
      expect(problems, isNotEmpty);
      expect(problems.first, contains('白名单'));
    });

    test('圆角范围 0.5x–2x', () {
      expect(ThemePackTokens.validate({'light': {'radius.md': 30.0}}), isNotEmpty);
      expect(ThemePackTokens.validate({'light': {'radius.md': 2.0}}), isNotEmpty);
      expect(ThemePackTokens.validate({'light': {'radius.md': 6.0}}), isEmpty);
      expect(ThemePackTokens.validate({'light': {'radius.md': 24.0}}), isEmpty);
    });

    test('颜色格式校验', () {
      expect(ThemePackTokens.validate({'light': {'brand.primary': '7B8BCF'}}), isNotEmpty);
      expect(ThemePackTokens.validate({'light': {'brand.primary': '#7B8BCF'}}), isEmpty);
      expect(ThemePackTokens.validate({'light': {'brand.primary': '#FF7B8BCF'}}), isEmpty);
    });


    test('顶层只允许 light / dark', () {
      final problems = ThemePackTokens.validate({
        'light': <String, Object?>{},
        'sepia': <String, Object?>{},
      });
      expect(problems, isNotEmpty);
    });
  });

  group('manifest 校验', () {
    test('合法清单通过', () {
      final manifest = ThemePackManifest.tryParse(validManifest())!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isEmpty);
    });

    test('schema 不符', () {
      final manifest = ThemePackManifest.tryParse(validManifest(schema: 2))!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('id 非法', () {
      for (final id in ['A', 'has space', 'a' * 41, '中文']) {
        final manifest = ThemePackManifest.tryParse(validManifest(id: id))!;
        expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty, reason: id);
      }
    });

    test('版本号格式', () {
      final manifest = ThemePackManifest.tryParse(validManifest(version: 'v1'))!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('minAppVersion 高于当前版本时拒绝', () {
      final manifest = ThemePackManifest.tryParse(validManifest(minAppVersion: '9.0.0'))!;
      final problems = manifest.validate(currentAppVersion: '1.7.6');
      expect(problems, isNotEmpty);
      expect(problems.first, contains('9.0.0'));
    });

    test('未知 source', () {
      final manifest = ThemePackManifest.tryParse(validManifest(source: 'p2p'))!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('license 必填', () {
      final manifest = ThemePackManifest.tryParse(validManifest(license: '  '))!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('assets 为空', () {
      final manifest = ThemePackManifest.tryParse(validManifest(assets: []))!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('资产路径不安全', () {
      for (final path in ['../escape.png', '/etc/passwd', 'assets\\win.png']) {
        final manifest = ThemePackManifest.tryParse(
          validManifest(assets: [
            {'path': path, 'sha256': 'b' * 64, 'bytes': 10},
          ]),
        )!;
        expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty, reason: path);
      }
    });

    test('sha256 格式错误', () {
      final manifest = ThemePackManifest.tryParse(
        validManifest(assets: [
          {'path': 'a.png', 'sha256': 'XYZ', 'bytes': 10},
        ]),
      )!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('bytes 与资产总和一致才通过', () {
      final bad = ThemePackManifest.tryParse(validManifest(bytes: 9999))!;
      expect(bad.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('未知 capability 被拒绝', () {
      final manifest = ThemePackManifest.tryParse(
        validManifest(capabilities: {'teleport': true}),
      )!;
      expect(manifest.validate(currentAppVersion: '1.7.6'), isNotEmpty);
    });

    test('结构缺字段时 tryParse 返回 null', () {
      expect(ThemePackManifest.tryParse({'schema': 1}), isNull);
      expect(ThemePackManifest.tryParse(null), isNull);
      expect(ThemePackManifest.tryParse('not a map'), isNull);
    });
  });

  group('版本比较', () {
    test('语义化比较', () {
      expect(ThemePackManifest.compareVersions('1.7.6', '1.7.5'), greaterThan(0));
      expect(ThemePackManifest.compareVersions('1.7.6', '1.7.6'), 0);
      expect(ThemePackManifest.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(ThemePackManifest.compareVersions('2.0.0', '1.99.99'), greaterThan(0));
    });
  });

  group('整包装载', () {
    test('合法包 ok', () {
      final result = loadThemePack(
        manifestJson: validManifest(),
        tokensJson: validTokens(),
        rootPath: '/tmp/pack',
        isBuiltin: false,
        currentAppVersion: '1.7.6',
      );
      expect(result.ok, isTrue);
      expect(result.pack!.id, 'shenli-joy13');
      expect(result.pack!.light.brandPrimary, isNotNull);
    });

    test('缺 tokens.json 时失败', () {
      final result = loadThemePack(
        manifestJson: validManifest(),
        tokensJson: null,
        rootPath: '/tmp/pack',
        isBuiltin: false,
        currentAppVersion: '1.7.6',
      );
      expect(result.ok, isFalse);
      expect(result.problems.join(), contains('tokens.json'));
    });

    test('manifest 结构非法时失败', () {
      final result = loadThemePack(
        manifestJson: {'schema': 'x'},
        tokensJson: validTokens(),
        rootPath: '/tmp/pack',
        isBuiltin: false,
        currentAppVersion: '1.7.6',
      );
      expect(result.ok, isFalse);
      expect(result.problems.first, contains('manifest.json'));
    });
  });
}
