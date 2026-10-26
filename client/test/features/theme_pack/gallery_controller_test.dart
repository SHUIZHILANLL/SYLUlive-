import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/features/theme_pack/application/theme_gallery_controller.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_importer.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_paths.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_store.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack.dart';

import 'store_importer_test.dart' show buildPack;

void main() {
  late Directory root;
  late ThemePackStore store;
  late ThemePackImporter importer;
  late ThemeGalleryController controller;
  late List<ThemePack?> appliedCalls;

  setUp(() {
    root = Directory.systemTemp.createTempSync('theme_ctrl_test_');
    store = ThemePackStore(ThemePackPaths(root), currentAppVersion: '1.7.6');
    importer = ThemePackImporter(store: store, currentAppVersion: '1.7.6');
    appliedCalls = <ThemePack?>[];
    controller = ThemeGalleryController(
      store: store,
      importer: importer,
      onApplied: appliedCalls.add,
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Future<File> writePack(String id, {String version = '1.0.0'}) async {
    final file = File('${root.path}/$id.syltheme');
    await file.writeAsBytes(buildPack(id: id, version: version));
    return file;
  }

  test('初始 load 后为空且状态 ready', () async {
    await controller.load();
    expect(controller.status, ThemeGalleryStatus.ready);
    expect(controller.packs, isEmpty);
    expect(controller.appliedId, isNull);
  });

  test('导入后进入列表但不自动应用', () async {
    final file = await writePack('p1');
    final outcomes = await controller.importPaths([file.path]);
    expect(outcomes.single.ok, isTrue);
    await controller.load();
    expect(controller.packs.length, 1);
    expect(controller.appliedId, isNull, reason: '导入不应自动应用');
    expect(appliedCalls, isEmpty);
  });

  test('apply 会回调主题层并持久化', () async {
    final file = await writePack('p1');
    await controller.importPaths([file.path]);
    await controller.load();
    final ok = await controller.apply('p1');
    expect(ok, isTrue);
    expect(appliedCalls.last?.id, 'p1');
    expect(controller.appliedId, 'p1');
    expect(await store.loadAppliedId(), 'p1');
    expect(controller.appliedPack?.id, 'p1');
  });

  test('reset 回到默认主题', () async {
    final file = await writePack('p1');
    await controller.importPaths([file.path]);
    await controller.load();
    await controller.apply('p1');
    await controller.reset();
    expect(controller.appliedId, isNull);
    expect(appliedCalls.last, isNull, reason: 'reset 应通知主题层回默认');
    expect(await store.loadAppliedId(), isNull);
  });

  test('删除当前应用包：先回退默认再删除', () async {
    final file = await writePack('p1');
    await controller.importPaths([file.path]);
    await controller.load();
    await controller.apply('p1');
    await controller.remove('p1');
    expect(appliedCalls.last, isNull);
    expect(controller.appliedId, isNull);
    expect(controller.packs, isEmpty);
    expect(await store.loadIndex(), isEmpty);
  });

  test('批量导入：成功与失败分别汇总', () async {
    final okFile = await writePack('p1');
    final badFile = File('${root.path}/bad.syltheme')..writeAsBytesSync([0, 1, 2]);
    final outcomes = await controller.importPaths([okFile.path, badFile.path]);
    expect(outcomes.where((o) => o.ok).length, 1);
    expect(outcomes.where((o) => !o.ok).length, 1);
    expect(outcomes.last.problems, isNotEmpty);
  });

  test('包目录被外部删除后 load 会自愈并回退默认', () async {
    final file = await writePack('p1');
    await controller.importPaths([file.path]);
    await controller.load();
    await controller.apply('p1');

    // 模拟用户在文件管理器里删掉包目录
    final dir = store.paths.packDir('p1', '1.0.0');
    dir.deleteSync(recursive: true);

    final fresh = ThemeGalleryController(
      store: store,
      importer: importer,
      onApplied: appliedCalls.add,
    );
    await fresh.load();
    expect(fresh.packs, isEmpty);
    expect(fresh.appliedId, isNull);
    expect(appliedCalls.last, isNull, reason: '包消失后应回退默认主题');
  });

  test('索引损坏不会让 load 失败', () async {
    await store.paths.ensureLayout();
    File('${root.path}/index.json').writeAsStringSync('{not json');
    await controller.load();
    expect(controller.status, ThemeGalleryStatus.ready);
  });
}
