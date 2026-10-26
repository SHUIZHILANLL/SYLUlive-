import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/app_radius.dart';
import '../../../theme/app_theme_tokens.dart';
import '../application/theme_gallery_controller.dart';
import 'widgets/theme_sample_card.dart';

/// 主题详情：壁纸横幅 + 真实组件样例（含明暗切换）+ 预览图轮播 + 应用/删除。
class ThemeDetailScreen extends StatefulWidget {
  const ThemeDetailScreen({
    super.key,
    required this.controller,
    required this.packId,
  });

  final ThemeGalleryController controller;
  final String packId;

  @override
  State<ThemeDetailScreen> createState() => _ThemeDetailScreenState();
}

class _ThemeDetailScreenState extends State<ThemeDetailScreen> {
  bool _previewDark = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final pack = controller.packs.where((p) => p.id == widget.packId).toList();
    if (pack.isEmpty) {
      // 包被删掉了（例如另一个入口删除了它）
      return Scaffold(
        appBar: AppBar(title: const Text('主题')),
        body: const Center(child: Text('主题包已不存在')),
      );
    }
    final current = pack.first;
    final applied = controller.isApplied(current.id);
    final banner = _bannerFile(current.assetPath, const [
      'assets/banner_detail.jpg',
      'assets/wallpaper_portrait.jpg',
      'assets/wallpaper_lock.jpg',
    ]);

    return Scaffold(
      appBar: AppBar(title: Text(current.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          if (banner != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.file(banner, height: 260, fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          ThemeSampleCard(
            pack: current,
            isDark: _previewDark,
            onToggle: () => setState(() => _previewDark = !_previewDark),
          ),
          _MetaRow(label: '版本', value: 'v${current.version}'),
          _MetaRow(label: '来源', value: current.manifest.source),
          _MetaRow(label: '授权', value: current.manifest.license),
          if (current.manifest.author.isNotEmpty)
            _MetaRow(label: '作者', value: current.manifest.author),
          _MetaRow(
            label: '能力',
            value: [
              if (current.manifest.capability('font')) '字体',
              if (current.manifest.capability('mascot')) '角色',
              if (current.manifest.capability('icons')) '图标',
              if (current.manifest.capability('radius')) '圆角',
            ].join(' · ').ifEmpty('仅壁纸与配色'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              if (!current.isBuiltin)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : _remove,
                    child: const Text('删除'),
                  ),
                ),
              if (!current.isBuiltin) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _busy || applied ? null : _apply,
                  child: Text(_busy ? '应用中…' : (applied ? '已应用' : '应用主题')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  File? _bannerFile(String Function(String) resolve, List<String> candidates) {
    for (final candidate in candidates) {
      final file = File(resolve(candidate));
      if (file.existsSync()) return file;
    }
    return null;
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    final ok = await widget.controller.apply(widget.packId);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已应用主题' : '应用失败，已保持原主题')),
    );
    if (ok && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个主题包？'),
        content: const Text('删除后需要重新导入。若它正在使用中，会先回到默认主题。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    await widget.controller.remove(widget.packId);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: TextStyle(fontSize: 12, color: tokens.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(fontSize: 12, color: tokens.textPrimary)),
          ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
