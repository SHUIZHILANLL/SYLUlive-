import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/theme_pack.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_radius.dart';
import '../../../../theme/app_theme_tokens.dart';

/// 主题库卡片：封面 + 名称 + 体积 + 当前徽标 + 能力标签。
class ThemePackCard extends StatelessWidget {
  const ThemePackCard({
    super.key,
    required this.pack,
    required this.applied,
    required this.onTap,
    this.sizeBytes,
  });

  final ThemePack pack;
  final bool applied;
  final VoidCallback onTap;
  final int? sizeBytes;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final cover = _coverFile();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: tokens.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: applied ? (pack.light.brandPrimary ?? AppColors.brandPrimary) : tokens.outline,
            width: applied ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image.file(cover, fit: BoxFit.cover)
                  else
                    ColoredBox(color: pack.light.brandPrimary ?? AppColors.brandSurfaceLight),
                  if (applied)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _Badge(
                        text: '使用中',
                        color: pack.light.brandPrimary ?? AppColors.brandPrimary,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pack.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tokens.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  PaletteSwatches(palette: pack.light),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    if (pack.isBuiltin) parts.add('内置');
    if (sizeBytes != null) {
      parts.add('${(sizeBytes! / 1024 / 1024).toStringAsFixed(1)} MB');
    } else {
      parts.add('v${pack.version}');
    }
    final caps = <String>[
      if (pack.manifest.capability('font')) '字体',
      if (pack.manifest.capability('mascot')) '角色',
      if (pack.manifest.capability('icons')) '图标',
    ];
    if (caps.isNotEmpty) parts.add(caps.join('/'));
    return parts.join(' · ');
  }

  File? _coverFile() {
    for (final candidate in const [
      'assets/wallpaper_portrait.jpg',
      'assets/wallpaper_portrait.png',
      'assets/mascot_sleep.jpg',
    ]) {
      if (!pack.hasAsset(candidate)) continue;
      final file = File(pack.assetPath(candidate));
      if (file.existsSync()) return file;
    }
    for (final preview in pack.manifest.preview) {
      final file = File(pack.assetPath(preview.path));
      if (file.existsSync()) return file;
    }
    return null;
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: const Text(
        '使用中',
        style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 四色圆点色卡：品牌色 / 标签底 / 次强调 / 表面色。
class PaletteSwatches extends StatelessWidget {
  const PaletteSwatches({super.key, required this.palette, this.size = 14});

  final dynamic palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final colors = <Color?>[
      palette.brandPrimary as Color?,
      palette.tagBackground as Color?,
      palette.accentSecondary as Color?,
      palette.surfacePrimary as Color?,
    ].whereType<Color>().toList();
    if (colors.isEmpty) {
      return Text('无配色', style: TextStyle(fontSize: 10, color: tokens.textSecondary));
    }
    return Row(
      children: [
        for (final color in colors)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.outline, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}
