import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../widgets/campus/campus_theme.dart';

/// 页面脚手架背景色。
///
/// 启用「自定义背景 / 主题包壁纸」时返回透明 —— 让全局背景层
/// （`GlobalBackgroundWrapper` → `CustomBackgroundLayer`）透出来；
/// 否则保持原来的米色/深色底。
///
/// 为什么需要它：Wallpaper 画在全局壳的最底层，但页面自己的
/// `Scaffold(backgroundColor: …)` 会把整页刷成不透明色，壁纸就被盖住了。
Color scaffoldBackgroundFor(BuildContext context, {bool? isDark}) {
  final dark = isDark ?? Theme.of(context).brightness == Brightness.dark;

  // ThemeProvider 允许缺失：大量页面级测试直接 mount 单个 Screen，
  // 没有挂 Provider 树。硬依赖会让这些测试整片失败
  // （ProviderNotFoundException），所以这里降级成"没有壁纸"。
  ThemeProvider? provider;
  try {
    provider = Provider.of<ThemeProvider>(context, listen: false);
  } on ProviderNotFoundException {
    provider = null;
  }

  if (provider != null && provider.shouldShowCustomBackground) {
    return Colors.transparent;
  }
  return dark ? CampusTheme.darkBg : CampusTheme.bg;
}
