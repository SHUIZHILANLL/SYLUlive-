import 'theme_pack_tokens.dart';

/// 主题包清单中的一个资产条目（带完整性校验信息）。
class ThemePackAsset {
  const ThemePackAsset({
    required this.path,
    required this.sha256,
    required this.bytes,
  });

  /// 包内相对路径，如 `assets/wallpaper_portrait.jpg`。
  final String path;

  /// 小写十六进制 SHA-256。
  final String sha256;

  final int bytes;

  static ThemePackAsset? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final path = raw['path'];
    final sha = raw['sha256'];
    final size = raw['bytes'];
    if (path is! String || sha is! String || size is! int) return null;
    return ThemePackAsset(path: path, sha256: sha, bytes: size);
  }
}

/// `manifest.json` 的类型化视图。
///
/// 解析只做"结构是否可用"，语义校验交给 [validate]，
/// 由导入流程决定是拒绝还是降级。
class ThemePackManifest {
  const ThemePackManifest({
    required this.schema,
    required this.id,
    required this.name,
    required this.version,
    required this.minAppVersion,
    required this.source,
    required this.author,
    required this.license,
    required this.licenseText,
    required this.bytes,
    required this.assets,
    required this.preview,
    required this.capabilities,
    this.themeVersion,
  });

  final int schema;
  final String id;
  final String name;
  final String version;
  final String minAppVersion;
  final String source;
  final String author;
  final String license;
  final String licenseText;
  final int bytes;
  final List<ThemePackAsset> assets;
  final List<ThemePackAsset> preview;
  final Map<String, bool> capabilities;
  final String? themeVersion;

  static const Set<String> allowedSources = {'builtin', 'imported', 'remote'};
  static final RegExp idPattern = RegExp(r'^[a-z0-9-]{2,40}$');
  static final RegExp semverPattern = RegExp(r'^\d+\.\d+\.\d+$');
  static final RegExp sha256Pattern = RegExp(r'^[a-f0-9]{64}$');

  bool capability(String key) => capabilities[key] ?? false;

  /// 结构解析；字段缺失或类型错误时返回 null（= 不是合法清单）。
  static ThemePackManifest? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final schema = raw['schema'];
    final id = raw['id'];
    final name = raw['name'];
    final version = raw['version'];
    final minAppVersion = raw['minAppVersion'];
    final source = raw['source'];
    if (schema is! int || id is! String || name is! String || version is! String) {
      return null;
    }
    if (minAppVersion is! String || source is! String) return null;

    final assets = <ThemePackAsset>[];
    final rawAssets = raw['assets'];
    if (rawAssets is List) {
      for (final item in rawAssets) {
        final asset = ThemePackAsset.tryParse(item);
        if (asset != null) assets.add(asset);
      }
    }
    final preview = <ThemePackAsset>[];
    final rawPreview = raw['preview'];
    if (rawPreview is List) {
      for (final item in rawPreview) {
        final asset = ThemePackAsset.tryParse(item);
        if (asset != null) preview.add(asset);
      }
    }

    final capabilities = <String, bool>{};
    final rawCaps = raw['capabilities'];
    if (rawCaps is Map) {
      rawCaps.forEach((key, value) {
        if (value is bool) capabilities[key.toString()] = value;
      });
    }

    return ThemePackManifest(
      schema: schema,
      id: id,
      name: name,
      version: version,
      minAppVersion: minAppVersion,
      source: source,
      author: raw['author'] is String ? raw['author'] as String : '',
      license: raw['license'] is String ? raw['license'] as String : '',
      licenseText: raw['licenseText'] is String ? raw['licenseText'] as String : '',
      bytes: raw['bytes'] is int ? raw['bytes'] as int : 0,
      assets: assets,
      preview: preview,
      capabilities: capabilities,
      themeVersion: raw['themeVersion'] is String ? raw['themeVersion'] as String : null,
    );
  }

  /// 语义校验。返回问题列表，空列表表示可安装。
  ///
  /// [currentAppVersion] 是当前 App 版本（形如 `1.7.6`），用于 `minAppVersion` 判定。
  List<String> validate({required String currentAppVersion}) {
    final problems = <String>[];

    if (schema != ThemePackTokens.schemaVersion) {
      problems.add('schema 期望 ${ThemePackTokens.schemaVersion}，实际 $schema');
    }
    if (!idPattern.hasMatch(id)) {
      problems.add('id 必须是 2–40 位小写字母/数字/连字符，实际 "$id"');
    }
    if (name.trim().isEmpty || name.characters > 80) {
      problems.add('name 不能为空且不超过 80 字符');
    }
    if (!semverPattern.hasMatch(version)) {
      problems.add('version 必须是 x.y.z，实际 "$version"');
    }
    if (!semverPattern.hasMatch(minAppVersion)) {
      problems.add('minAppVersion 必须是 x.y.z，实际 "$minAppVersion"');
    } else if (compareVersions(minAppVersion, currentAppVersion) > 0) {
      problems.add('需要 App $minAppVersion 及以上，当前 $currentAppVersion');
    }
    if (!allowedSources.contains(source)) {
      problems.add('source 只能是 ${allowedSources.join(" / ")}，实际 "$source"');
    }
    if (license.trim().isEmpty) {
      problems.add('license 必填（素材与字体授权）');
    }
    if (assets.isEmpty) {
      problems.add('assets 不能为空');
    }
    for (final asset in assets) {
      problems.addAll(_validateAsset(asset));
    }
    for (final asset in preview) {
      problems.addAll(_validateAsset(asset));
    }
    for (final key in capabilities.keys) {
      if (!ThemePackTokens.allowedCapabilities.contains(key)) {
        problems.add('capabilities.$key 不是已知能力');
      }
    }
    if (bytes > 0) {
      final sum = assets.fold<int>(0, (acc, a) => acc + a.bytes) +
          preview.fold<int>(0, (acc, a) => acc + a.bytes);
      if (sum != bytes) {
        problems.add('manifest.bytes=$bytes 与资产总和 $sum 不一致');
      }
    }
    return problems;
  }

  List<String> _validateAsset(ThemePackAsset asset) {
    final problems = <String>[];
    final path = asset.path;
    if (path.isEmpty ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').contains('..')) {
      problems.add('资产路径不安全: "$path"');
    }
    if (!sha256Pattern.hasMatch(asset.sha256)) {
      problems.add('资产 sha256 格式错误: ${asset.path}');
    }
    if (asset.bytes <= 0) {
      problems.add('资产大小为 0: ${asset.path}');
    }
    return problems;
  }

  /// 语义化版本比较：a > b 返回正数。
  static int compareVersions(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (var i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va - vb;
    }
    return 0;
  }
}

extension on String {
  int get characters => runes.length;
}
