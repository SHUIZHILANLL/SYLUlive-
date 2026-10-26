import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/theme_pack.dart';
import 'builtin_pack.dart';
import '../domain/theme_pack_manifest.dart';
import '../domain/theme_pack_tokens.dart';
import 'theme_pack_paths.dart';

/// 一条已安装记录（`index.json` 的一项）。
class InstalledPackRecord {
  const InstalledPackRecord({
    required this.id,
    required this.version,
    required this.name,
    required this.bytes,
    required this.source,
    required this.installedAt,
  });

  final String id;
  final String version;
  final String name;
  final int bytes;
  final String source;
  final String installedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'version': version,
        'name': name,
        'bytes': bytes,
        'source': source,
        'installedAt': installedAt,
      };

  static InstalledPackRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final version = raw['version'];
    if (id is! String || version is! String) return null;
    return InstalledPackRecord(
      id: id,
      version: version,
      name: raw['name'] is String ? raw['name'] as String : id,
      bytes: raw['bytes'] is int ? raw['bytes'] as int : 0,
      source: raw['source'] is String ? raw['source'] as String : 'imported',
      installedAt: raw['installedAt'] is String ? raw['installedAt'] as String : '',
    );
  }
}

/// 安装结果。
class InstallOutcome {
  const InstallOutcome({required this.ok, this.pack, this.problems = const []});

  final bool ok;
  final ThemePack? pack;
  final List<String> problems;
}

/// 主题包的设备侧仓库：索引读写、原子安装、删除、配额、损坏自愈。
///
/// 设计要点：
/// - **原子性**：先解到 `.staging`，全部校验通过才 `rename` 进正式目录并写 `.verified`；
/// - **可恢复**：索引损坏 → 备份坏文件 + 扫目录重建；半装目录（缺 `.verified`）→ 移入 `.trash`；
/// - **配额**：单包 ≤50MB、总量 ≤500MB，导入前就拒绝，避免事后爆盘。
class ThemePackStore {
  ThemePackStore(
    this.paths, {
    this.currentAppVersion = '1.7.6',
    this.maxPackBytes = 50 * 1024 * 1024,
    this.maxTotalBytes = 500 * 1024 * 1024,
  });

  final ThemePackPaths paths;
  final String currentAppVersion;
  final int maxPackBytes;
  final int maxTotalBytes;

  static const int indexSchema = 1;

  ThemePackPaths get _paths => paths;

  // ------------------------------------------------------------------ 索引
  Future<List<InstalledPackRecord>> loadIndex() async {
    await _paths.ensureLayout();
    final file = _paths.indexFile;
    if (!file.existsSync()) {
      return _rebuildIndex();
    }
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map || raw['packs'] is! List) {
        return _rebuildIndex(reason: '索引结构不合法');
      }
      final records = <InstalledPackRecord>[];
      for (final item in raw['packs'] as List) {
        final record = InstalledPackRecord.tryParse(item);
        if (record == null) continue;
        // 目录不存在 = 被外部删了，直接丢
        if (!_paths.packDir(record.id, record.version).existsSync()) continue;
        records.add(record);
      }
      return records;
    } catch (_) {
      return _rebuildIndex(reason: '索引损坏');
    }
  }

  Future<String?> loadAppliedId() async {
    final file = _paths.indexFile;
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map && raw['appliedId'] is String) return raw['appliedId'] as String;
    } catch (_) {
      // 忽略：损坏时由 loadIndex 触发重建
    }
    return null;
  }

  Future<void> _writeIndex(List<InstalledPackRecord> records, String? appliedId) async {
    await _paths.ensureLayout();
    final payload = {
      'schema': indexSchema,
      'appliedId': appliedId,
      'packs': records.map((r) => r.toJson()).toList(),
    };
    await _paths.indexFile.writeAsString(jsonEncode(payload), flush: true);
  }

  /// 索引损坏/缺失时按目录重建。
  Future<List<InstalledPackRecord>> _rebuildIndex({String? reason}) async {
    final file = _paths.indexFile;
    if (file.existsSync()) {
      final backup = File('${file.path}.broken-${DateTime.now().millisecondsSinceEpoch}');
      try {
        await file.rename(backup.path);
      } catch (_) {
        // 备份失败不阻塞重建
      }
    }
    final records = <InstalledPackRecord>[];
    for (final entity in _paths.root.listSync()) {
      if (entity is! Directory) continue;
      final name = entity.path.split(RegExp(r'[\\/]')).last;
      if (!name.contains('@')) continue;
      final parts = name.split('@');
      if (parts.length != 2) continue;
      final marker = File('${entity.path}/.verified');
      if (!marker.existsSync()) {
        // 半装目录：移入 trash，不计数
        await _moveToTrash(entity);
        continue;
      }
      final manifestFile = File('${entity.path}/manifest.json');
      if (!manifestFile.existsSync()) {
        await _moveToTrash(entity);
        continue;
      }
      try {
        final manifest = jsonDecode(await manifestFile.readAsString());
        final record = InstalledPackRecord.tryParse({
          'id': parts[0],
          'version': parts[1],
          'name': manifest is Map ? manifest['name'] : parts[0],
          'bytes': _dirBytes(entity),
          'source': manifest is Map ? manifest['source'] : 'imported',
          'installedAt': manifest is Map ? manifest['builtAt'] : '',
        });
        if (record != null) records.add(record);
      } catch (_) {
        await _moveToTrash(entity);
      }
    }
    records.sort((a, b) => a.id.compareTo(b.id));
    await _writeIndex(records, null);
    if (reason != null) {
      // 重建原因仅用于日志，不影响返回值
      stderr.writeln('[theme_pack] 索引重建：$reason');
    }
    return records;
  }

  /// 确保内置默认包存在（首次启动或用户删过时补装）。
  ///
  /// 幂等：已存在就直接返回；不动用户导入的包。
  Future<void> ensureBuiltin() async {
    await _paths.ensureLayout();
    final marker = _paths.verifiedMarker(BuiltinThemePack.id, BuiltinThemePack.version);
    if (marker.existsSync()) return;
    await install(
      manifestJson: BuiltinThemePack.manifest(minAppVersion: currentAppVersion),
      tokensJson: BuiltinThemePack.tokens,
      files: {BuiltinThemePack.assetPath: BuiltinThemePack.placeholderBytes},
      isBuiltin: true,
    );
  }

  // ------------------------------------------------------------------ 读取  /// 读取一个已安装包的完整模型；缺失/损坏返回 null。
  Future<ThemePack?> readPack(String id, String version) async {
    final dir = _paths.packDir(id, version);
    if (!dir.existsSync() || !_paths.verifiedMarker(id, version).existsSync()) return null;
    try {
      final manifestJson = jsonDecode(await File('${dir.path}/manifest.json').readAsString());
      final tokensJson = jsonDecode(await File('${dir.path}/tokens.json').readAsString());
      final result = loadThemePack(
        manifestJson: manifestJson,
        tokensJson: tokensJson,
        rootPath: dir.path,
        isBuiltin: manifestJson is Map && manifestJson['source'] == 'builtin',
        currentAppVersion: currentAppVersion,
      );
      return result.pack;
    } catch (_) {
      return null;
    }
  }

  Future<int> totalBytes() async {
    var sum = 0;
    for (final record in await loadIndex()) {
      sum += record.bytes;
    }
    return sum;
  }

  // ------------------------------------------------------------------ 安装
  /// 从暂存内容安装一个包（内容已由 importer 校验过 sha256 与 tokens）。
  Future<InstallOutcome> install({
    required Map<String, Object?> manifestJson,
    required Map<String, Object?> tokensJson,
    required Map<String, List<int>> files,
    bool isBuiltin = false,
  }) async {
    final manifest = ThemePackManifest.tryParse(manifestJson);
    if (manifest == null) {
      return const InstallOutcome(ok: false, problems: ['manifest.json 结构不合法']);
    }

    // 配额（覆盖同 id 旧版本时按差值算）
    final records = await loadIndex();
    final existing = records.where((r) => r.id == manifest.id).toList();
    final existingBytes = existing.fold<int>(0, (a, r) => a + r.bytes);
    final incoming = files.values.fold<int>(0, (a, b) => a + b.length);
    if (incoming > maxPackBytes) {
      return InstallOutcome(
        ok: false,
        problems: [
          '包体积 ${_mb(incoming)} 超过单包上限 ${_mb(maxPackBytes)}'
        ],
      );
    }
    final total = await totalBytes();
    if (total - existingBytes + incoming > maxTotalBytes) {
      return InstallOutcome(
        ok: false,
        problems: [
          '超过设备配额 ${_mb(maxTotalBytes)}（已用 ${_mb(total)}，删除旧主题后再试）'
        ],
      );
    }

    await _paths.ensureLayout();
    final staging = Directory('${_paths.stagingDir.path}/${manifest.id}-${manifest.version}-'
        '${DateTime.now().microsecondsSinceEpoch}');
    await staging.create(recursive: true);

    try {
      for (final entry in files.entries) {
        final target = File('${staging.path}/${entry.key}');
        await target.parent.create(recursive: true);
        await target.writeAsBytes(entry.value, flush: true);
      }
      await File('${staging.path}/manifest.json')
          .writeAsString(jsonEncode(manifestJson), flush: true);
      await File('${staging.path}/tokens.json')
          .writeAsString(jsonEncode(tokensJson), flush: true);

      final target = _paths.packDir(manifest.id, manifest.version);
      for (final old in existing) {
        if (old.version == manifest.version) continue;
        await _moveToTrash(_paths.packDir(old.id, old.version));
      }
      if (target.existsSync()) {
        await target.delete(recursive: true);
      }
      await staging.rename(target.path);
      await _paths
          .verifiedMarker(manifest.id, manifest.version)
          .writeAsString(DateTime.now().toIso8601String(), flush: true);

      final updated = <InstalledPackRecord>[
        ...records.where((r) => r.id != manifest.id),
        InstalledPackRecord(
          id: manifest.id,
          version: manifest.version,
          name: manifest.name,
          bytes: incoming,
          source: isBuiltin ? 'builtin' : manifest.source,
          installedAt: DateTime.now().toIso8601String(),
        ),
      ];
      await _writeIndex(updated, await loadAppliedId());

      final pack = await readPack(manifest.id, manifest.version);
      return InstallOutcome(ok: pack != null, pack: pack,
          problems: pack == null ? ['安装后读取失败'] : const []);
    } catch (error) {
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
      return InstallOutcome(ok: false, problems: ['写入失败：$error']);
    }
  }

  // ------------------------------------------------------------------ 删除
  /// 删除一个包；若删的是当前应用包，先把 appliedId 清空（由调用方回退默认主题）。
  Future<bool> remove(String id, String version) async {
    final dir = _paths.packDir(id, version);
    final applied = await loadAppliedId();
    if (!dir.existsSync()) {
      await _writeIndex((await loadIndex()).where((r) => r.id != id).toList(), applied);
      return false;
    }
    await _moveToTrash(dir);
    final records = (await loadIndex()).where((r) => r.id != id).toList();
    final nextApplied = applied == id ? null : applied;
    await _writeIndex(records, nextApplied);
    return true;
  }

  /// 记录"当前应用"的包 id。
  Future<void> setAppliedId(String? id) async {
    await _writeIndex(await loadIndex(), id);
  }

  Future<void> clearTrash() async {
    if (!_paths.trashDir.existsSync()) return;
    for (final entity in _paths.trashDir.listSync()) {
      try {
        await entity.delete(recursive: true);
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------------ 工具
  Future<void> _moveToTrash(Directory dir) async {
    if (!dir.existsSync()) return;
    await _paths.ensureLayout();
    final name = dir.path.split(RegExp(r'[\\/]')).last;
    final target = '${_paths.trashDir.path}/$name-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await dir.rename(target);
    } catch (_) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  int _dirBytes(Directory dir) {
    var sum = 0;
    try {
      for (final f in dir.listSync(recursive: true)) {
        if (f is File) sum += f.lengthSync();
      }
    } catch (_) {}
    return sum;
  }

  static String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';

  /// 计算 sha256（importer 与测试共用）。
  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  /// 读取包内某资产路径的绝对路径（壁纸等）。
  String assetAbsolutePath(ThemePack pack, String relative) => pack.assetPath(relative);

  /// tokens 白名单校验（供 importer 复用）。
  static List<String> validateTokens(Map<String, dynamic> tokens) =>
      ThemePackTokens.validate(tokens);
}
