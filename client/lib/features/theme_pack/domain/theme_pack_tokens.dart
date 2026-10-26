/// 主题包 tokens 的白名单与校验规则。
///
/// **必须与转换器 `tools/theme_pack_converter/pack.py` 保持一致**：
/// 转换器用同一份白名单拒绝非法包，App 侧导入时再验一次，
/// 两边都不通过就不许安装。
library;

/// 主题包 token 契约。
abstract final class ThemePackTokens {
  /// manifest.json 的 schema 版本。
  static const int schemaVersion = 1;

  /// 允许主题包覆盖的键。
  static const Set<String> allowed = {
    // 背景与表面
    'bg.primary',
    'surface.primary',
    'surface.secondary',
    'surface.elevated',
    // 文字与边框
    'text.primary',
    'text.secondary',
    'text.disabled',
    'border.normal',
    'border.subtle',
    // 品牌与强调
    'brand.primary',
    'accent.secondary',
    'tag.bg',
    'tag.text',
    'message.outgoing',
    'composer.input',
    // 圆角（0.5x – 2x）
    'radius.sm',
    'radius.md',
    'radius.lg',
    'radius.sheet',
  };

  /// 永不可覆盖：状态语义色（可用性）与全部间距（改间距必破布局）。
  static const List<String> forbiddenPrefixes = [
    'success',
    'warning',
    'danger',
    'info',
    'spacing',
  ];

  /// 永不可覆盖：胶囊圆角是语义值。
  static const String forbiddenPillRadius = 'radius.pill';

  /// 圆角原值，用于范围校验（0.5x – 2x）。
  static const Map<String, double> radiusDefaults = {
    'radius.sm': 8.0,
    'radius.md': 12.0,
    'radius.lg': 16.0,
    'radius.sheet': 24.0,
  };

  static const double radiusMinFactor = 0.5;
  static const double radiusMaxFactor = 2.0;

  /// 包可声明的能力键。
  static const Set<String> allowedCapabilities = {
    'font',
    'icons',
    'radius',
  'mascotBadge',
  'stateArt',
    'mascot',
      'loadingAnim',
  };

  static const String lightKey = 'light';
  static const String darkKey = 'dark';

  static final RegExp _hexColor = RegExp(r'^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$');

  /// 校验 tokens 结构，返回问题列表；空列表表示通过。
  static List<String> validate(Map<String, dynamic> tokens) {
    final problems = <String>[];
    for (final key in tokens.keys) {
      if (key != lightKey && key != darkKey) {
        problems.add('tokens 顶层只允许 "$lightKey" / "$darkKey"，发现 "$key"');
      }
    }
    for (final mode in const [lightKey, darkKey]) {
      final block = tokens[mode];
      if (block == null) continue;
      if (block is! Map) {
        problems.add('tokens.$mode 必须是对象');
        continue;
      }
      block.forEach((rawKey, value) {
        final key = rawKey.toString();
        problems.addAll(validateEntry(mode, key, value));
      });
    }
    return problems;
  }

  /// 校验单个 token 条目。
  static List<String> validateEntry(String mode, String key, Object? value) {
    final problems = <String>[];
    if (key == forbiddenPillRadius) {
      problems.add('$mode.$key 属于语义值，不可覆盖');
      return problems;
    }
    for (final prefix in forbiddenPrefixes) {
      if (key == prefix || key.startsWith('$prefix.')) {
        problems.add('$mode.$key 属于不可覆盖项（状态语义色 / 间距）');
        return problems;
      }
    }
    if (!allowed.contains(key)) {
      problems.add('$mode.$key 不在白名单内');
      return problems;
    }

    if (ThemePackTokens.radiusDefaults.containsKey(key)) {
      if (value is! num) {
        problems.add('$mode.$key 必须是数字');
        return problems;
      }
      final base = ThemePackTokens.radiusDefaults[key]!;
      final min = base * radiusMinFactor;
      final max = base * radiusMaxFactor;
      final v = value.toDouble();
      if (v < min || v > max) {
        problems.add('$mode.$key=$value 超出允许范围 $min–$max');
      }
      return problems;
    }

    if (value is! String || !_hexColor.hasMatch(value)) {
      problems.add('$mode.$key 必须是 #RRGGBB 或 #AARRGGBB');
    }
    return problems;
  }
}
