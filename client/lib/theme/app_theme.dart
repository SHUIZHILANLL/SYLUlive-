import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_radius.dart';
import '../widgets/campus/campus_theme.dart';

class AppTheme {
  // 主题色 — 全局统一为品牌青绿
  /// 主题包提供的品牌种子色；null 表示用 App 默认品牌色。
  static Color? _brandSeedOverride;

  /// 由 ThemeProvider 在应用/取消主题包时调用。
  static void setBrandSeed(Color? color) => _brandSeedOverride = color;

  static bool get hasBrandSeed => _brandSeedOverride != null;

  /// 实际生效的品牌色：有主题包就用包里的，否则用默认。
  static Color get primaryColor => _brandSeedOverride ?? AppColors.brandPrimary;

  /// 深色模式强调色：把品牌色往白里提一档，保证深底上够亮又不刺眼。
  ///
  /// 之前这里是硬编码 #7ED6C5，换背景提色时开关/滑块/指示器都不跟着变。
  static Color _liftForDark(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withLightness(hsl.lightness < 0.62 ? 0.66 : hsl.lightness)
        .withSaturation(hsl.saturation.clamp(0.45, 0.75))
        .toColor();
  }
  static const Color secondaryColor = AppColors.info;
  static const Color accentColor = AppColors.warning;

  // 圆角 — 国产 UI 紧凑风格
  // 半径跟随主题包（AppRadius 支持运行时覆盖），所以不能是 const。
  static double get borderRadius => AppRadius.md;
  static double get borderRadiusSmall => AppRadius.sm;
  static double get borderRadiusLarge => AppRadius.lg;

  // 阴影
  static const double shadowBlur = 10.0;
  static const double shadowOffset = 2.0;

  // 间距 — 紧凑
  static const double spacing = 12.0;
  static const double spacingSmall = 6.0;
  static const double spacingLarge = 20.0;

  static ThemeData _baseTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 必须显式指定：ThemeData 在深色模式下默认 primaryColor 取
      // colorScheme.surface（近黑），导致 NavigationRail 选中项、各种
      // Theme.of(context).primaryColor 强调色在深色背景上几乎不可见。
      // 浅色取 scheme.primary；深色取「品牌色提亮版」——原来是写死的
      // 薄荷绿 #7ED6C5，导致换背景提色后开关/滑块颜色不跟着变。
      primaryColor: brightness == Brightness.dark
          ? _liftForDark(primaryColor)
          : scheme.primary,
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? CampusTheme.darkBg : CampusTheme.bg,
      canvasColor:
          brightness == Brightness.dark ? CampusTheme.darkBg : CampusTheme.bg,
      fontFamily: 'NotoSansCJKsc',
      fontFamilyFallback: const [
        'Noto Color Emoji',
        'Segoe UI Emoji',
        'Apple Color Emoji',
      ],
      // 全局紧凑密度
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 48,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      // 卡片 — 紧凑圆角
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      // 按钮 — 紧凑
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        ),
      ),
      // 输入框 — 紧凑
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
      // 对话框 — 紧凑圆角
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusLarge),
        ),
      ),
      // 底部弹窗
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      // Tab 栏
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: brightness == Brightness.dark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight,
        indicatorColor: scheme.primary,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      // 进度条
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.15),
      ),
      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return null;
        }),
      ),
      // 导航栏
      navigationBarTheme: NavigationBarThemeData(
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      // FloatingActionButton
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
      ),
    );
  }

  static ThemeData get lightTheme => _baseTheme(Brightness.light);
  static ThemeData get darkTheme => _baseTheme(Brightness.dark);
}
