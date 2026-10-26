import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/features/theme_pack/data/builtin_pack.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_importer.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_paths.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_store.dart';

/// 构造一个合法的 `.syltheme` 字节流（真实 zip，含 sha256）。
Uint8List buildPack({
  String id = 'p1',
  String version = '1.0.0',
  String minAppVersion = '1.7.6',
  Map<String, Object?>? tokens,
  Map<String, List<int>>? assets,
  Map<String, Object?>? extraManifest,
}) {
  final assetFiles = assets ??
      {
        'assets/wallpaper_portrait.jpg': List<int>.generate(64, (i) => i),
      };
  final previewFiles = <String, List<int>>{
    'assets/preview_home.jpg': List<int>.generate(16, (i) => 100 + i),
  };

  final assetEntries = <Map<String, Object?>>[];
  assetFiles.forEach((path, bytes) {
    assetEntries.add({
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    });
  });
  final previewEntries = <Map<String, Object?>>[];
  previewFiles.forEach((path, bytes) {
    previewEntries.add({
      'path': path,
      'sha256': sha256.convert(bytes).toString(),
      'bytes': bytes.length,
    });
  });

  final total = [
    ...assetFiles.values,
    ...previewFiles.values,
  ].fold<int>(0, (a, b) => a + b.length);

  final manifest = <String, Object?>{
    'schema': 1,
    'id': id,
    'name': '测试主题 $id',
    'version': version,
    'minAppVersion': minAppVersion,
    'source': 'imported',
    'author': 'test',
    'license': 'OFL-1.1',
    'licenseText': 'n/a',
    'bytes': total,
    'assets': assetEntries,
    'preview': previewEntries,
    'capabilities': {'mascot': true, 'radius': true},
    ...?extraManifest,
  };

  final archive = Archive();
  void add(String name, List<int> data) {
    archive.addFile(ArchiveFile.bytes(name, data));
  }

  add('manifest.json', utf8.encode(jsonEncode(manifest)));
  add('tokens.json', utf8.encode(jsonEncode(tokens ??
      {
        'light': {'brand.primary': '#FF7B8BCF', 'radius.md': 14.0},
        'dark': {'brand.primary': '#FF8E9BD6'},
      })));
  assetFiles.forEach(add);
  previewFiles.forEach(add);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

ThemePackStore newStore(Directory root) => ThemePackStore(
      ThemePackPaths(root),
      currentAppVersion: '1.7.6',
      maxPackBytes: 2 * 1024 * 1024,
      maxTotalBytes: 3 * 1024 * 1024,
    );

void main() {
  late Directory root;
  late ThemePackStore store;
  late ThemePackImporter importer;

  setUp(() {
    root = Directory.systemTemp.createTempSync('theme_pack_test_');
    store = newStore(root);
    importer = ThemePackImporter(store: store, currentAppVersion: '1.7.6');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('importer', () {
    test('合法包导入成功并可读回', () async {
      final outcome = await importer.importBytes(buildPack(), fileName: 'p1.syltheme');
      expect(outcome.ok, isTrue, reason: outcome.problems.join('；'));
      final pack = await store.readPack('p1', '1.0.0');
      expect(pack, isNotNull);
      expect(pack!.name, '测试主题 p1');
      expect(pack.light.brandPrimary, isNotNull);
    });

    test('缺 manifest.json', () async {
      final archive = Archive()..addFile(ArchiveFile.bytes('tokens.json', utf8.encode('{}')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final outcome = await importer.importBytes(bytes);
      expect(outcome.ok, isFalse);
      expect(outcome.summary, contains('manifest.json'));
    });

    test('缺 tokens.json', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode('{}')));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final outcome = await importer.importBytes(bytes);
      expect(outcome.ok, isFalse);
      expect(outcome.summary, contains('tokens.json'));
    });

    test('不是 zip', () async {
      final outcome = await importer.importBytes(Uint8List.fromList(utf8.encode('nope')));
      expect(outcome.ok, isFalse);
    });

    test('资产 sha256 不匹配被拒', () async {
      final good = buildPack();
      final archive = ZipDecoder().decodeBytes(good);
      // 篡改壁纸内容但保留原清单
      final tampered = Archive();
      for (final file in archive) {
        if (!file.isFile) continue;
        final data = file.name.contains('wallpaper')
            ? List<int>.generate(64, (i) => 255 - i)
            : file.readBytes()!;
        tampered.addFile(ArchiveFile.bytes(file.name, data));
      }
      final bytes = Uint8List.fromList(ZipEncoder().encode(tampered));
      final outcome = await importer.importBytes(bytes);
      expect(outcome.ok, isFalse);
      expect(outcome.problems.join(), contains('sha256'));
      // 失败不留残骸
      expect(store.loadIndex().then((v) => v.length), completion(0));
    });

    test('非法 token（禁改项）被拒', () async {
      final outcome = await importer.importBytes(buildPack(tokens: {
        'light': {'danger': '#FFFF0000'},
      }));
      expect(outcome.ok, isFalse);
    });

    test('minAppVersion 过高被拒', () async {
      final outcome = await importer.importBytes(buildPack(minAppVersion: '9.9.9'));
      expect(outcome.ok, isFalse);
      expect(outcome.problems.join(), contains('9.9.9'));
    });

    test('扩展名不对时 importFile 报错', () async {
      final file = File('${root.path}/x.zip')..writeAsBytesSync(buildPack());
      final outcome = await importer.importFile(file);
      expect(outcome.ok, isFalse);
      expect(outcome.summary, contains('.syltheme'));
    });

    test('批量导入：一个成功一个失败，各自汇总', () async {
      final okFile = File('${root.path}/good.syltheme')..writeAsBytesSync(buildPack());
      final badFile = File('${root.path}/bad.syltheme')..writeAsBytesSync([1, 2, 3]);
      final results = await importer.importFiles([okFile, badFile]);
      expect(results.length, 2);
      expect(results[0].ok, isTrue);
      expect(results[1].ok, isFalse);
    });
  });

  group('store', () {
    test('索引初始为空', () async {
      expect(await store.loadIndex(), isEmpty);
    });

    test('索引损坏时重建', () async {
      await store.paths.ensureLayout();
      File('${root.path}/index.json').writeAsStringSync('{broken');
      final index = await store.loadIndex();
      expect(index, isEmpty);
      // 坏文件被备份
      final backups = root
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('index.json.broken-'))
          .toList();
      expect(backups, isNotEmpty);
    });

    test('半装目录（缺 .verified）被移入 trash', () async {
      final dir = Directory('${root.path}/half@1.0.0')..createSync(recursive: true);
      File('${dir.path}/manifest.json').writeAsStringSync('{}');
      final index = await store.loadIndex();
      expect(index, isEmpty);
      expect(dir.existsSync(), isFalse);
    });

    test('配额：单包超限被拒', () async {
      final big = List<int>.generate(3 * 1024 * 1024, (i) => i % 256);
      final outcome = await importer.importBytes(buildPack(assets: {
        'assets/wallpaper_portrait.jpg': big,
      }));
      expect(outcome.ok, isFalse);
      expect(outcome.summary, contains('上限'));
    });

    test('安装后 setAppliedId / remove', () async {
      await importer.importBytes(buildPack(id: 'p1'), fileName: 'p1.syltheme');
      await store.setAppliedId('p1');
      expect(await store.loadAppliedId(), 'p1');

      final removed = await store.remove('p1', '1.0.0');
      expect(removed, isTrue);
      expect(await store.loadIndex(), isEmpty);
      expect(await store.loadAppliedId(), isNull, reason: '删掉当前应用包应清空 appliedId');
    });

    test('同 id 新版本安装会替换旧版本', () async {
      await importer.importBytes(buildPack(id: 'p1', version: '1.0.0'));
      await importer.importBytes(buildPack(id: 'p1', version: '1.1.0'));
      final index = await store.loadIndex();
      expect(index.length, 1);
      expect(index.first.version, '1.1.0');
    });
  });

  group('内置默认包', () {
    test('ensureBuiltin 安装并可读回，且标记为内置', () async {
      await store.ensureBuiltin();
      final index = await store.loadIndex();
      expect(index.length, 1);
      expect(index.first.id, BuiltinThemePack.id);
      expect(index.first.source, 'builtin');
      final pack = await store.readPack(BuiltinThemePack.id, BuiltinThemePack.version);
      expect(pack, isNotNull);
      expect(pack!.isBuiltin, isTrue, reason: '内置包不允许删除');
      expect(pack.light.brandPrimary, isNotNull);
    });

    test('ensureBuiltin 幂等', () async {
      await store.ensureBuiltin();
      await store.ensureBuiltin();
      expect((await store.loadIndex()).length, 1);
    });

    test('内置包不会挤掉用户导入的包', () async {
      await store.ensureBuiltin();
      await importer.importBytes(buildPack(id: 'p-user'), fileName: 'p-user.syltheme');
      final index = await store.loadIndex();
      expect(index.length, 2);
      expect(index.any((r) => r.id == 'p-user'), isTrue);
      expect(index.any((r) => r.id == BuiltinThemePack.id), isTrue);
    });
  });
}