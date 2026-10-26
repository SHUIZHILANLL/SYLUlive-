import 'package:flutter/material.dart';

import 'theme_pack_tokens.dart';

/// 一套已解析的主题包外观值（浅色或深色）。
///
/// 只保存"包实际声明过的"值；没声明的键返回 `null`，
/// 由消费方（`AppColors` / `AppRadius` / `ThemeProvider`）回落到默认值。
/// 这样"缺 token 逐条回落"才成立，而不是整包失败。
@immutable
class ThemePalette {
  const ThemePalette({
    this.colors = const {},
    this.radii = const {},
  });

  /// 空板：所有 token 都未覆盖。
  static const ThemePalette empty = ThemePalette();

  /// token → 颜色（仅白名单内的颜色类键）。
  final Map<String, Color> colors;

  /// token → 圆角（已在导入期夹紧到 0.5x–2x）。
  final Map<String, double> radii;

  bool get isEmpty => colors.isEmpty && radii.isEmpty;

  Color? color(String key) => colors[key];
  double? radius(String key) => radii[key];

  // 常用便捷取值
  Color? get brandPrimary => colors['brand.primary'];
  Color? get accentSecondary => colors['accent.secondary'];
  Color? get tagBackground => colors['tag.bg'];
  Color? get tagText => colors['tag.text'];
  Color? get background => colors['bg.primary'];
  Color? get surfacePrimary => colors['surface.primary'];

  /// 从 `tokens.json` 的一个分支解析。
  ///
  /// 非法条目**逐条丢弃**（不抛异常），保证一个坏 token 不会让整包不可用；
  /// 导入流程另外会用 [ThemePackTokens.validate] 给出精确报错。
  factory ThemePalette.fromTokens(Object? block) {
    if (block is! Map) return ThemePalette.empty;
    final colors = <String, Color>{};
    final radii = <String, double>{};

    block.forEach((rawKey, value) {
      final key = rawKey.toString();
      if (ThemePackTokens.validateEntry(ThemePackTokens.lightKey, key, value).isNotEmpty) {
        return; // 非法条目直接跳过
      }
      if (ThemePackTokens.radiusDefaults.containsKey(key)) {
        radii[key] = (value as num).toDouble();
        return;
      }
      final color = parseHexColor(value as String);
      if (color != null) colors[key] = color;
    });

    return ThemePalette(colors: colors, radii: radii);
  }

  /// `#RRGGBB` / `#AARRGGBB` → Color；非法返回 null。
  static Color? parseHexColor(String? value) {
    if (value == null) return null;
    var hex = value.trim();
    if (!hex.startsWith('#')) return null;
    hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }

  @override
  String toString() =>
      'ThemePalette(colors: ${colors.length}, radii: ${radii.length})';
}
