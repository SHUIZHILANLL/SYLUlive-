import 'package:flutter/material.dart';

import 'theme_pack_manifest.dart';
import 'theme_palette.dart';
import 'theme_pack_tokens.dart';

/// 一个已解析、已通过校验的主题包。
///
/// S1 阶段只做**纯内存**构造（不碰文件系统）；解压、sha256 校验、
/// 落盘与索引由 S2 的 `ThemePackStore` / S3 的 `ThemePackImporter` 负责。
class ThemePack {
  const ThemePack({
    required this.manifest,
    required this.light,
    required this.dark,
    required this.rootPath,
    required this.isBuiltin,
  });

  final ThemePackManifest manifest;

  /// 浅色外观（只含包声明过的 token）。
  final ThemePalette light;

  /// 深色外观。包未声明 dark 时由 `deriveDark` 生成。
  final ThemePalette dark;

  /// 包内容所在目录（解压后的根目录）；内置包为资源路径前缀。
  final String rootPath;

  final bool isBuiltin;

  String get id => manifest.id;
  String get name => manifest.name;
  String get version => manifest.version;

  /// 包内资产的绝对路径。
  String assetPath(String relative) =>
      rootPath.endsWith('/') ? '$rootPath$relative' : '$rootPath/$relative';

  bool hasAsset(String relative) =>
      manifest.assets.any((a) => a.path == relative) ||
      manifest.preview.any((a) => a.path == relative);

  static ThemePack? fromParts({
    required Object? manifestJson,
    required Object? tokensJson,
    required String rootPath,
    required bool isBuiltin,
  }) {
    final manifest = ThemePackManifest.tryParse(manifestJson);
    if (manifest == null) return null;
    final tokens = tokensJson is Map ? tokensJson : const <String, dynamic>{};
    final light = ThemePalette.fromTokens(tokens[ThemePackTokens.lightKey]);
    final darkRaw = tokens[ThemePackTokens.darkKey];
    final dark = darkRaw == null ? deriveDark(light) : ThemePalette.fromTokens(darkRaw);
    return ThemePack(
      manifest: manifest,
      light: light,
      dark: dark,
      rootPath: rootPath,
      isBuiltin: isBuiltin,
    );
  }

  /// 深色派生：包没给 dark 时，按亮度翻转粗略推导，并标记为"派生"。
  ///
  /// 只推导颜色，不推导圆角与玻璃（那两项与明暗无关）。
  static ThemePalette deriveDark(ThemePalette light) {
    final colors = <String, Color>{};
    light.colors.forEach((key, value) {
      final hsl = HSLColor.fromColor(value);
      final isBrandLike = key.startsWith('brand.') ||
          key.startsWith('accent.') ||
          key.startsWith('tag.');
      // 强调色在深底上要提亮；背景/表面要压暗
      final double newLightness;
      if (isBrandLike) {
        newLightness = (hsl.lightness + 0.18).clamp(0.0, 1.0);
      } else if (key.startsWith('bg.') || key.startsWith('surface.')) {
        newLightness = (hsl.lightness * 0.16).clamp(0.0, 1.0);
      } else {
        newLightness = (1.0 - hsl.lightness).clamp(0.0, 1.0);
      }
      colors[key] = hsl.withLightness(newLightness).toColor();
    });
    return ThemePalette(
      colors: colors,
      radii: light.radii,
    );
  }
}

/// 解析 + 校验的结果。
class ThemePackLoadResult {
  const ThemePackLoadResult({this.pack, this.problems = const []});

  final ThemePack? pack;
  final List<String> problems;

  bool get ok => pack != null && problems.isEmpty;
}

/// 从两份 JSON 构建并校验（导入流程的主入口）。
ThemePackLoadResult loadThemePack({
  required Object? manifestJson,
  required Object? tokensJson,
  required String rootPath,
  required bool isBuiltin,
  required String currentAppVersion,
}) {
  final manifest = ThemePackManifest.tryParse(manifestJson);
  if (manifest == null) {
    return const ThemePackLoadResult(problems: ['manifest.json 结构不合法或缺少必填字段']);
  }
  final problems = <String>[];
  problems.addAll(manifest.validate(currentAppVersion: currentAppVersion));

  final tokens = tokensJson is Map ? tokensJson : null;
  if (tokens == null) {
    problems.add('缺少 tokens.json 或结构不合法');
  } else {
    problems.addAll(ThemePackTokens.validate(Map<String, dynamic>.from(tokens)));
  }

  final pack = ThemePack.fromParts(
    manifestJson: manifestJson,
    tokensJson: tokensJson,
    rootPath: rootPath,
    isBuiltin: isBuiltin,
  );
  return ThemePackLoadResult(pack: pack, problems: problems);
}
