import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/features/theme_pack/application/theme_gallery_controller.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_importer.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_paths.dart';
import 'package:shenliyuan/features/theme_pack/data/theme_pack_store.dart';
import 'package:shenliyuan/features/theme_pack/domain/theme_pack.dart';
import 'package:shenliyuan/features/theme_pack/presentation/theme_detail_screen.dart';
import 'package:shenliyuan/features/theme_pack/presentation/theme_gallery_screen.dart';
import 'package:shenliyuan/features/theme_pack/presentation/widgets/pack_mascot.dart';
import 'package:shenliyuan/theme/app_theme.dart';
import 'package:shenliyuan/widgets/state_placeholder.dart';

import '../../helpers/load_test_fonts.dart';

/// 截图工装：用真实主题包渲染主题库/详情页并落盘 PNG，供人工验收。
///
/// 需要 `THEME_PACK_DEMO` 指向一个 `.syltheme`；缺省整体跳过（CI 安全）。
/// 两条环境纪律：
/// 1. 真实文件 IO 必须放进 `tester.runAsync`，否则 FakeAsync 不推进 dart:io Future；
/// 2. 页面里有无限动画（loading 圈），不能用 `pumpAndSettle`。
void main() {
  final demoPackPath = Platform.environment['THEME_PACK_DEMO'];
  final outputDir = Platform.environment['THEME_PACK_SHOTS'] ??
      '${Directory.current.path}/build/theme_pack_shots';

  /// 让所有文本都走已加载的 CJK 字体（否则 Material 默认字体会渲染成方框）。
  ThemeData withCjk(ThemeData base) {
    const family = 'NotoSansCJKsc';
    final body = base.textTheme.apply(fontFamily: family, fontFamilyFallback: const [family]);
    return base.copyWith(
      textTheme: body,
      primaryTextTheme:
          base.primaryTextTheme.apply(fontFamily: family, fontFamilyFallback: const [family]),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(textStyle: const TextStyle(fontFamily: family, fontSize: 14, fontWeight: FontWeight.w600)),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        titleTextStyle: (base.appBarTheme.titleTextStyle ?? body.titleLarge)
            ?.copyWith(fontFamily: family, fontFamilyFallback: const [family]),
      ),
    );
  }

  testWidgets('渲染主题库与详情页截图', (tester) async {
    // ignore: avoid_print
    print('STEP fonts...');
    await loadTestFonts();
    // ignore: avoid_print
    print('STEP fonts ok');

    final root = Directory.systemTemp.createTempSync('theme_shot_');
    final store = ThemePackStore(ThemePackPaths(root), currentAppVersion: '1.7.6');
    final importer = ThemePackImporter(store: store, currentAppVersion: '1.7.6');
    final controller = ThemeGalleryController(store: store, importer: importer);

    String? importProblem;
    // ignore: avoid_print
    print('STEP import...');
    await tester.runAsync(() async {
      await store.ensureBuiltin();
      final outcome = await importer.importFile(File(demoPackPath!));
      if (!outcome.ok) importProblem = outcome.problems.join('；');
      await controller.load();
    });
    expect(importProblem, isNull, reason: importProblem);
    expect(controller.packs, isNotEmpty);

    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    Future<void> settle() async {
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    /// 预热图片：手动 resolve 并灌进 imageCache。
    /// 不能用 precacheImage —— 它在 widget test 里会一直 pending。
    Future<void> warm(List<String> relativePaths) async {
      final pack = controller.packs.firstWhere((p) => !p.isBuiltin);
      for (final relative in relativePaths) {
        final file = File(pack.assetPath(relative));
        if (!file.existsSync()) continue;
        await tester.runAsync(() async {
          final stream = FileImage(file).resolve(ImageConfiguration.empty);
          final done = Completer<void>();
          late ImageStreamListener listener;
          listener = ImageStreamListener(
            (_, __) => done.isCompleted ? null : done.complete(),
            onError: (_, __) => done.isCompleted ? null : done.complete(),
          );
          stream.addListener(listener);
          try {
            await done.future.timeout(const Duration(seconds: 5));
          } catch (_) {}
          stream.removeListener(listener);
        });
      }
      await settle();
    }

    Future<void> capture(String name, GlobalKey key) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory(outputDir);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        File('${dir.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        // ignore: avoid_print
        print('SHOT $name -> ${dir.path}/$name.png');
      });
    }

    final demoPackId = controller.packs.firstWhere((p) => !p.isBuiltin).id;
    await tester.runAsync(() => controller.apply(demoPackId));
    await warm(_coverCandidates);
    final demoPack = controller.packs.firstWhere((p) => !p.isBuiltin);
    ThemePackMascot.setPath(demoPack.assetPath('assets/mascot_idle.png'));
    await warm(const ['assets/mascot_idle.png']);

    // ---- 1. 主题库
    final galleryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: galleryKey,
        child: MaterialApp(
          theme: withCjk(AppTheme.lightTheme),
          home: ThemeGalleryScreen(controller: controller, enablePicker: false, autoLoad: false),
        ),
      ),
    );
    print('STEP gallery pumped');
    await settle();
    print('STEP gallery settled');
    await capture('01-gallery', galleryKey);

    // ---- 2. 详情页（浅色）
    final detailKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: detailKey,
        child: MaterialApp(
          theme: withCjk(AppTheme.lightTheme),
          home: ThemeDetailScreen(controller: controller, packId: demoPackId),
        ),
      ),
    );
    await warm(_detailAssets(demoPack));
    await settle();
    await capture('02-detail-light', detailKey);

    // ---- 3. 深色预览
    final toggle = find.text('浅色');
    if (toggle.evaluate().isNotEmpty) {
      await tester.tap(toggle);
      await settle();
      await capture('03-detail-dark', detailKey);
    }

    // ---- 4. 空态
    final emptyStore = ThemePackStore(
      ThemePackPaths(Directory.systemTemp.createTempSync('theme_empty_')),
      currentAppVersion: '1.7.6',
    );
    final emptyController = ThemeGalleryController(
      store: emptyStore,
      importer: ThemePackImporter(store: emptyStore, currentAppVersion: '1.7.6'),
    );
    await tester.runAsync(emptyController.load);
    final emptyKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: emptyKey,
        child: MaterialApp(
          theme: withCjk(AppTheme.lightTheme),
          home: ThemeGalleryScreen(controller: emptyController, enablePicker: false, autoLoad: false),
        ),
      ),
    );
    await settle();
    await capture('04-gallery-empty', emptyKey);
    // ---- 5. 全局空态（StatePlaceholder 接入主题包插画后的样子）
    final stateKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: stateKey,
        child: MaterialApp(
          theme: withCjk(AppTheme.lightTheme),
          home: const Scaffold(
            body: StatePlaceholder(
              title: '还没有内容',
              subtitle: '这条空态现在会显示主题包里的角色',
              icon: Icons.inbox_outlined,
            ),
          ),
        ),
      ),
    );
    await settle();
    await capture('05-state-placeholder', stateKey);
  }, skip: demoPackPath == null || demoPackPath.isEmpty);
}

const _coverCandidates = [
  'assets/wallpaper_portrait.jpg',
  'assets/wallpaper_portrait.png',
  'assets/mascot_sleep.jpg',
];

List<String> _detailAssets(ThemePack pack) => [
      'assets/wallpaper_portrait.jpg',
      'assets/wallpaper_lock.jpg',
      ...pack.manifest.preview.map((p) => p.path),
    ];
