import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 内置的「默认主题」空壳包。
///
/// 不提供壁纸与插画，只声明品牌默认色，作用有三：
/// 1. 主题库里始终有一个可点、可查看的基线（而不是"隐式默认"）；
/// 2. 用户删光导入的包后仍有一个可见的回落目标；
/// 3. 体积 < 1 KB，随代码走，不占 assets 目录。
///
/// 带一个 1×1 透明 PNG 是因为 `manifest.assets` 不允许为空
/// （见 `ThemePackManifest.validate`），用 70 字节占位满足结构约束。
abstract final class BuiltinThemePack {
  static const String id = 'sylu-default';
  static const String version = '1.0.0';
  static const String name = '沈理默认';
  static const String assetPath = 'assets/placeholder.png';

  /// 1×1 透明 PNG（70 字节）。
  static const String _placeholderBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNgYGBgAAAABQABeqhXUAAAAABJRU5ErkJggg==';

  static Uint8List get placeholderBytes => base64Decode(_placeholderBase64);

  static String get placeholderSha256 => sha256.convert(placeholderBytes).toString();

  /// 与 App 默认品牌色一致，避免"默认主题"看起来像另一个主题。
  static const Map<String, Object?> tokens = {
    'light': {'brand.primary': '#FF147C72'},
    'dark': {'brand.primary': '#FF7ED6C5'},
  };

  static Map<String, Object?> manifest({required String minAppVersion}) {
    final bytes = placeholderBytes.length;
    return {
      'schema': 1,
      'id': id,
      'name': name,
      'version': version,
      'minAppVersion': minAppVersion,
      'source': 'builtin',
      'author': 'SYLUlive',
      'license': 'MIT',
      'licenseText': '应用自带，无第三方素材',
      'bytes': bytes,
      'assets': [
        {'path': assetPath, 'sha256': placeholderSha256, 'bytes': bytes},
      ],
      'preview': <Map<String, Object?>>[],
      'capabilities': <String, bool>{},
    };
  }
}
