import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/theme_pack.dart';
import '../domain/theme_pack_manifest.dart';
import '../domain/theme_pack_tokens.dart';
import 'theme_pack_store.dart';

/// 一次导入的结果（成功或失败，都带可读原因）。
class ImportOutcome {
  const ImportOutcome({
    required this.fileName,
    required this.ok,
    this.pack,
    this.problems = const [],
  });

  final String fileName;
  final bool ok;
  final ThemePack? pack;
  final List<String> problems;

  String get summary =>
      ok ? '已安装 ${pack?.name ?? ''}' : problems.isEmpty ? '导入失败' : problems.first;
}

/// 把 `.syltheme`（zip）读进来并交给 [ThemePackStore] 安装。
///
/// 校验顺序刻意"先便宜后昂贵"：
/// 结构 → schema/id/版本 → tokens 白名单 → 逐资产 sha256 → 配额（在 store 里）。
/// 任何一步失败都不会留下半个包。
class ThemePackImporter {
  ThemePackImporter({required this.store, required this.currentAppVersion});

  final ThemePackStore store;
  final String currentAppVersion;

  static const String manifestName = 'manifest.json';
  static const String tokensName = 'tokens.json';

  /// 从内存字节导入（测试与下载共用）。
  Future<ImportOutcome> importBytes(Uint8List bytes, {String fileName = 'pack.syltheme'}) async {
    if (bytes.length > store.maxPackBytes) {
      return ImportOutcome(
        fileName: fileName,
        ok: false,
        problems: ['包体积超过单包上限 ${(store.maxPackBytes / 1024 / 1024).toStringAsFixed(0)} MB'],
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (error) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['不是合法的 zip：$error']);
    }

    final entries = <String, ArchiveFile>{};
    for (final file in archive) {
      if (!file.isFile) continue;
      entries[file.name] = file;
    }

    final manifestFile = entries[manifestName];
    if (manifestFile == null) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['缺少 manifest.json']);
    }
    final tokensFile = entries[tokensName];
    if (tokensFile == null) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['缺少 tokens.json']);
    }

    final Map<String, Object?> manifestJson;
    final Map<String, Object?> tokensJson;
    try {
      final decodedManifest = jsonDecode(utf8.decode(manifestFile.readBytes()!));
      if (decodedManifest is! Map) {
        return ImportOutcome(fileName: fileName, ok: false, problems: ['manifest.json 不是对象']);
      }
      manifestJson = Map<String, Object?>.from(decodedManifest);
    } catch (error) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['manifest.json 解析失败：$error']);
    }
    try {
      final decodedTokens = jsonDecode(utf8.decode(tokensFile.readBytes()!));
      if (decodedTokens is! Map) {
        return ImportOutcome(fileName: fileName, ok: false, problems: ['tokens.json 不是对象']);
      }
      tokensJson = Map<String, Object?>.from(decodedTokens);
    } catch (error) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['tokens.json 解析失败：$error']);
    }

    final manifest = ThemePackManifest.tryParse(manifestJson);
    if (manifest == null) {
      return ImportOutcome(fileName: fileName, ok: false, problems: ['manifest.json 缺少必填字段']);
    }

    final problems = <String>[];
    problems.addAll(manifest.validate(currentAppVersion: currentAppVersion));
    problems.addAll(ThemePackTokens.validate(Map<String, dynamic>.from(tokensJson)));
    if (problems.isNotEmpty) {
      return ImportOutcome(fileName: fileName, ok: false, problems: problems);
    }

    // 逐资产核对 sha256 与大小；同时只把这些文件写盘（忽略包里多余条目，防夹带）
    final files = <String, List<int>>{};
    for (final asset in manifest.assets) {
      final entry = entries[asset.path];
      if (entry == null) {
        problems.add('包里缺少声明的资产：${asset.path}');
        continue;
      }
      final data = entry.readBytes()!;
      if (data.length != asset.bytes) {
        problems.add('资产大小不符：${asset.path}（声明 ${asset.bytes}，实际 ${data.length}）');
        continue;
      }
      final digest = ThemePackStore.sha256Hex(data);
      if (digest != asset.sha256) {
        problems.add('资产 sha256 不匹配：${asset.path}');
        continue;
      }
      files[asset.path] = data;
    }
    for (final preview in manifest.preview) {
      final entry = entries[preview.path];
      if (entry == null) {
        problems.add('包里缺少预览图：${preview.path}');
        continue;
      }
      final data = entry.readBytes()!;
      if (ThemePackStore.sha256Hex(data) != preview.sha256) {
        problems.add('预览图 sha256 不匹配：${preview.path}');
        continue;
      }
      files[preview.path] = data;
    }
    if (problems.isNotEmpty) {
      return ImportOutcome(fileName: fileName, ok: false, problems: problems);
    }

    final outcome = await store.install(
      manifestJson: manifestJson,
      tokensJson: tokensJson,
      files: files,
    );
    return ImportOutcome(
      fileName: fileName,
      ok: outcome.ok,
      pack: outcome.pack,
      problems: outcome.problems,
    );
  }

  /// 从本地文件导入（用户多选）。
  Future<ImportOutcome> importFile(File file) async {
    if (!file.existsSync()) {
      return ImportOutcome(fileName: file.path, ok: false, problems: ['文件不存在']);
    }
    final name = file.path.split(RegExp(r'[\\/]')).last;
    if (!name.toLowerCase().endsWith('.syltheme')) {
      return ImportOutcome(fileName: name, ok: false, problems: ['扩展名必须是 .syltheme']);
    }
    final bytes = await file.readAsBytes();
    return importBytes(Uint8List.fromList(bytes), fileName: name);
  }

  /// 批量导入：串行执行，逐个汇总（不因为一个失败就中断）。
  Future<List<ImportOutcome>> importFiles(List<File> files) async {
    final results = <ImportOutcome>[];
    for (final file in files) {
      results.add(await importFile(file));
    }
    return results;
  }
}
