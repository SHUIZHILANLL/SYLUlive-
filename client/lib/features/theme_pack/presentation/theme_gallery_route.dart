import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../providers/theme_provider.dart';
import '../../../theme/app_theme_tokens.dart';
import '../application/theme_gallery_controller.dart';
import '../data/theme_pack_importer.dart';
import '../data/theme_pack_paths.dart';
import '../data/theme_pack_store.dart';
import 'theme_gallery_screen.dart';

/// 主题库的路由壳：负责异步准备存储目录、组装控制器，并把"应用主题"
/// 接到 [ThemeProvider]（圆角 / 玻璃预设 / 壁纸 / 空态插画）。
///
/// 单独抽出来的原因：`ThemePackPaths.forApp()` 与 `PackageInfo` 都是异步的，
/// 而设置页是 StatelessWidget；把异步引导放在这一层，页面本身保持纯展示。
class ThemeGalleryRoute extends StatefulWidget {
  const ThemeGalleryRoute({super.key});

  @override
  State<ThemeGalleryRoute> createState() => _ThemeGalleryRouteState();
}

class _ThemeGalleryRouteState extends State<ThemeGalleryRoute> {
  ThemeGalleryController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      final paths = await ThemePackPaths.forApp();
      var version = '1.7.6';
      try {
        final info = await PackageInfo.fromPlatform();
        if (info.version.isNotEmpty) version = info.version;
      } catch (_) {
        // 读取版本失败就用兜底值：只影响 minAppVersion 校验的严格程度
      }
      final store = ThemePackStore(paths, currentAppVersion: version);
      final importer = ThemePackImporter(store: store, currentAppVersion: version);
      // 首次启动补装内置默认包，保证列表里始终有基线可点
      await store.ensureBuiltin();
      if (!mounted) return;
      final themeProvider = context.read<ThemeProvider>();
      final controller = ThemeGalleryController(
        store: store,
        importer: importer,
        onApplied: (pack) => unawaited(themeProvider.applyThemePack(pack)),
      );
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_error != null) {
      final tokens = AppThemeTokens.of(context);
      return Scaffold(
        appBar: AppBar(title: const Text('主题')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '主题模块初始化失败\n$_error',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            ),
          ),
        ),
      );
    }
    if (controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('主题')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return ThemeGalleryScreen(controller: controller);
  }
}
