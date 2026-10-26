import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/theme_pack.dart';
import '../../domain/theme_palette.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/app_radius.dart';
import '../../../../theme/app_theme_tokens.dart';

/// 「真实组件样例」：用包内 token 驱动 4 个真实样式的元素，
/// 让用户在应用前就能看到"换成这套主题后界面长什么样"。
///
/// 刻意只做 4 个元素（标题/卡片/标签/主按钮）+ 色卡：
/// 它们覆盖了底色、强调色、圆角、文字对比度这四个最容易翻车的维度，
/// 又不会诱导后续去改真实页面组件。
class ThemeSampleCard extends StatelessWidget {
  const ThemeSampleCard({
    super.key,
    required this.pack,
    required this.isDark,
    required this.onToggle,
  });

  final ThemePack pack;
  final bool isDark;
  final VoidCallback onToggle;

  ThemePalette get _palette => isDark ? pack.dark : pack.light;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final palette = _palette;
    final brand = palette.brandPrimary ?? AppColors.brandPrimary;
    final onBrand = _onColor(brand);
    final radiusMd = palette.radius('radius.md') ?? AppRadius.md;
    final radiusSm = palette.radius('radius.sm') ?? AppRadius.sm;
    final cardColor = palette.surfacePrimary ?? (isDark ? AppColors.surfaceMutedDark : tokens.cardBackground);
    // 深色预览时，周围 App 仍是浅色主题，文字色不能取 tokens（否则深底深字看不见）
    final textPrimary = isDark ? AppColors.textPrimaryDark : tokens.textPrimary;
    final textSecondary = isDark ? AppColors.textSecondaryDark : tokens.textSecondary;
    final divider = isDark ? AppColors.borderSubtleDark : tokens.divider;
    final tagBg = palette.tagBackground ?? tokens.tagBackground;
    final tagText = palette.tagText ?? tokens.tagText;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceSecondaryDark : tokens.cardBackground,
        borderRadius: BorderRadius.circular(radiusMd),
        border: Border.all(color: tokens.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '示例预览',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
              _ToggleChip(isDark: isDark, onTap: onToggle),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '校园通知',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '这是主题包里的文字颜色',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(radiusMd),
              border: Border.all(color: divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '卡片表面 + 圆角',
                  style: TextStyle(fontSize: 13, color: textPrimary),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(radiusSm),
                  ),
                  child: Text(
                    '标签',
                    style: TextStyle(
                      fontSize: 11,
                      color: tagText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: brand,
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              child: Center(
                child: Text(
                  '主按钮',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: onBrand,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 前景色：黑/白里对比度更高者（与转换器同算法）。
  static Color _onColor(Color background) {
    final luminance = background.computeLuminance();
    final onWhite = 1.05 / (luminance + 0.05);
    final onBlack = (luminance + 0.05) / 0.05;
    return onWhite >= onBlack ? Colors.white : Colors.black;
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({required this.isDark, required this.onTap});

  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: tokens.outline),
        ),
        child: Text(
          isDark ? '深色' : '浅色',
          style: TextStyle(fontSize: 11, color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// 包内预览图横向轮播（转换器抽的 6 张：桌面/锁屏/状态栏…）。
class PackPreviewCarousel extends StatelessWidget {
  const PackPreviewCarousel({super.key, required this.pack});

  final ThemePack pack;

  @override
  Widget build(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    final files = <File>[];
    for (final preview in pack.manifest.preview) {
      final file = File(pack.assetPath(preview.path));
      if (file.existsSync()) files.add(file);
    }
    if (files.isEmpty) {
      return Text('这个主题包没有预览图', style: TextStyle(fontSize: 12, color: tokens.textSecondary));
    }
    return SizedBox(
      height: 240,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: files.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.file(files[index], width: 120, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
