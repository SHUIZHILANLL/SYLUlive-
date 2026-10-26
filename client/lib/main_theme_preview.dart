// 仅用于「主题模块」的真机/模拟器预览，不参与正式发布。
//
// 用法：
//   flutter run -t lib/main_theme_preview.dart -d <device>
//   flutter build apk --debug --target-platform android-x64 -t lib/main_theme_preview.dart
//
// 首页是一页「组件秀」：按钮 / 开关 / 标签 / 进度条 / Tab / 卡片全部走
// `AppTheme` → `AppColors`，所以应用主题包后整页配色会一起变——
// 用来验证"美化到底生效了没有"最直观。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'features/theme_pack/data/theme_pack_importer.dart';
import 'features/theme_pack/data/theme_pack_paths.dart';
import 'features/theme_pack/data/theme_pack_store.dart';
import 'features/theme_pack/presentation/theme_gallery_route.dart';
import 'providers/theme_provider.dart';
import 'theme/app_colors.dart';
import 'theme/app_radius.dart';
import 'theme/app_theme.dart';
import 'widgets/app_shell.dart';
import 'widgets/state_placeholder.dart';

/// 随包携带的演示主题（预览入口启动时全部导入，幂等）。
const List<String> demoPackAssets = [
  'assets/demo/shenli-joy13.syltheme',
  'assets/demo/shenli-mayuri.syltheme',
];
const String appVersion = '1.7.6';

/// 预览入口自己的导航 key（buildAppShell 需要）。
final GlobalKey<NavigatorState> _previewNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _preparePacks();
  runApp(const ThemePreviewApp());
}

Future<void> _preparePacks() async {
  try {
    final paths = await ThemePackPaths.forApp();
    final store = ThemePackStore(paths, currentAppVersion: appVersion);
    final importer = ThemePackImporter(store: store, currentAppVersion: appVersion);
    await store.ensureBuiltin();
    for (final asset in demoPackAssets) {
      final data = await rootBundle.load(asset);
      final outcome = await importer.importBytes(
        data.buffer.asUint8List(),
        fileName: asset.split('/').last,
      );
      debugPrint('[theme-preview] $asset imported: ${outcome.ok} ${outcome.problems}');
    }
  } catch (error) {
    debugPrint('[theme-preview] prepare failed: $error');
  }
}

class ThemePreviewApp extends StatelessWidget {
  const ThemePreviewApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, provider, _) => MaterialApp(
          title: '主题预览',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: provider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          // 与正式 App 同一套全局壳 → 预览里也能看到角色水印
          builder: (context, child) => buildAppShell(
            context: context,
            child: child,
            navigatorKey: _previewNavigatorKey,
            enableUpdateGate: false,
          ),
          home: const ComponentsShowcase(),
        ),
      ),
    );
  }
}

/// 一页把所有"吃品牌色"的组件摆出来：应用主题前后对比最直接。
class ComponentsShowcase extends StatelessWidget {
  const ComponentsShowcase({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('组件秀'),
        actions: [
          IconButton(
            tooltip: '主题',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ThemeGalleryRoute()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          _Label('当前主题：${provider.appliedThemePackId ?? '默认'}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(onPressed: () {}, child: const Text('主按钮')),
              OutlinedButton(onPressed: () {}, child: const Text('次按钮')),
              TextButton(onPressed: () {}, child: const Text('文字按钮')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Chip(label: const Text('标签'), backgroundColor: AppColors.brandSurfaceLight),
              const SizedBox(width: 8),
              Badge(
                label: const Text('3'),
                child: Icon(Icons.notifications_outlined, color: scheme.primary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const LinearProgressIndicator(value: 0.62),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('卡片标题', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('卡片正文，用来看表面色与圆角是否跟着主题走。'),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Switch(value: true, onChanged: (_) {}),
                      const SizedBox(width: 12),
                      Checkbox(value: true, onChanged: (_) {}),
                    ],
                  ),
                  Slider(value: 0.4, onChanged: (_) {}),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DefaultTabController(
            length: 3,
            child: Column(
              children: [
                TabBar(
                  tabs: const [Tab(text: '最新'), Tab(text: '校园'), Tab(text: '关注')],
                  indicatorColor: scheme.primary,
                  labelColor: scheme.primary,
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brandSurfaceLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: AppColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Text('搜索框（品牌浅底）', style: TextStyle(color: AppColors.brandPrimaryStrong)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // 空态/状态插图预览（用的是主题包的 state_art）
          Container(
            height: 240,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const StatePlaceholder(
              title: '暂无内容',
              subtitle: '这条空态用的是主题包里状态插图',
              icon: Icons.inbox_outlined,
            ),
          ),
          const SizedBox(height: 16),
          _Label('圆角 sm=${AppRadius.sm.toStringAsFixed(1)} '
              'md=${AppRadius.md.toStringAsFixed(1)} '
              'lg=${AppRadius.lg.toStringAsFixed(1)}'),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
}
