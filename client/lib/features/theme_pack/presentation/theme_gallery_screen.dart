import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_theme_tokens.dart';
import '../application/theme_gallery_controller.dart';
import 'theme_detail_screen.dart';
import 'widgets/pack_mascot.dart';
import 'widgets/theme_pack_card.dart';

/// 主题库：列出已安装与内置主题，支持批量导入、进入详情、查看存储占用。
class ThemeGalleryScreen extends StatefulWidget {
  const ThemeGalleryScreen({
    super.key,
    required this.controller,
    this.enablePicker = true,
    this.autoLoad = true,
  });

  final ThemeGalleryController controller;

  /// 截图/测试时可关掉真实文件选择。
  final bool enablePicker;

  /// 是否在挂载时自动 load（测试里可关，由调用方先 load 好）。
  final bool autoLoad;

  @override
  State<ThemeGalleryScreen> createState() => _ThemeGalleryScreenState();
}

class _ThemeGalleryScreenState extends State<ThemeGalleryScreen> {
  int _totalBytes = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    if (widget.autoLoad) {
      widget.controller.load().then((_) => _refreshUsage());
    } else {
      _refreshUsage();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshUsage() async {
    final bytes = await widget.controller.totalBytes();
    if (mounted) setState(() => _totalBytes = bytes);
  }

  Future<void> _pickAndImport() async {
    if (!widget.enablePicker) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    final paths = result?.paths.whereType<String>().toList() ?? const <String>[];
    if (paths.isEmpty) return;
    final outcomes = await widget.controller.importPaths(paths);
    if (!mounted) return;
    await _refreshUsage();
    final ok = outcomes.where((o) => o.ok).length;
    final failed = outcomes.length - ok;
    final detail = outcomes.where((o) => !o.ok).map((o) => '· ${o.fileName}：${o.summary}').join('\n');
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导入完成：成功 $ok，失败 $failed'),
        content: failed == 0
            ? const Text('全部导入成功。')
            : SingleChildScrollView(child: Text(detail, style: const TextStyle(fontSize: 12))),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('好')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final tokens = AppThemeTokens.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('主题')),
      body: switch (controller.status) {
        ThemeGalleryStatus.idle || ThemeGalleryStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        ThemeGalleryStatus.failed => _ErrorState(
            message: controller.error ?? '加载失败',
            onRetry: () => controller.load(),
          ),
        ThemeGalleryStatus.ready => RefreshIndicator(
            onRefresh: () async {
              await controller.load();
              await _refreshUsage();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '已应用：${controller.appliedPack?.name ?? '默认主题'}',
                        style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: controller.importing ? null : _pickAndImport,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(controller.importing ? '导入中…' : '导入主题包'),
                    ),
                  ],
                ),
                Text(
                  '存储占用 ${( _totalBytes / 1024 / 1024).toStringAsFixed(1)} MB / 500 MB',
                  style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                if (controller.packs.isEmpty)
                  _EmptyState(onImport: _pickAndImport)
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 264,
                    ),
                    itemCount: controller.packs.length,
                    itemBuilder: (context, index) {
                      final pack = controller.packs[index];
                      return ThemePackCard(
                        pack: pack,
                        applied: controller.isApplied(pack.id),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ThemeDetailScreen(
                              controller: controller,
                              packId: pack.id,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        children: [
          // 有主题包插画时显示角色，否则回落到图标
          if (ThemePackMascot.available)
            const PackMascotImage(size: 120)
          else
            Icon(Icons.palette_outlined, size: 40, color: tokens.textSecondary),
          const SizedBox(height: 12),
          Text('还没有主题包', style: TextStyle(fontSize: 15, color: tokens.textPrimary)),
          const SizedBox(height: 6),
          Text(
            '导入 .syltheme 文件即可换壁纸与配色',
            style: TextStyle(fontSize: 12, color: tokens.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onImport, child: const Text('导入主题包')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36, color: tokens.error),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
