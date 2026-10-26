import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_text_scaler.dart';
import 'app_update_gate.dart';

/// `MaterialApp.builder` 的统一实现。
///
/// 收在一处的原因：正式 App（`app_bootstrap.dart`）和预览入口
/// （`main_theme_preview.dart`）需要**同一套**全局装饰——
/// 字号缩放、版本更新门、主题包角色水印。
/// 之前只写在 app_bootstrap 里，导致预览入口看不到水印。
///
/// 用法：
/// ```dart
/// MaterialApp(
///   builder: (context, child) => buildAppShell(
///     context: context,
///     child: child,
///     navigatorKey: appNavigatorKey,
///   ),
/// )
/// ```
Widget buildAppShell({
  required BuildContext context,
  required Widget? child,
  required GlobalKey<NavigatorState> navigatorKey,
  bool enableUpdateGate = true,
}) {
  final themeProvider = context.watch<ThemeProvider>();
  final mediaQuery = MediaQuery.of(context);
  final appTextScaler = AppTextScaler(
    mediaQuery.textScaler,
    themeProvider.fontSizePreset.scaleFactor,
  ).clamp(maxScaleFactor: AppTextScaler.maxScaleFactor);

  final content = child ?? const SizedBox.shrink();
  final app = MediaQuery(
    data: mediaQuery.copyWith(textScaler: appTextScaler),
    // 预览入口没有 AppUpdateCoordinator，可用 enableUpdateGate: false 跳过
    child: enableUpdateGate
        ? AppUpdateGate(navigatorKey: navigatorKey, child: content)
        : content,
  );

  // 全局壳只负责：字号缩放 + 版本门 +（原角色水印位，已按需求移除）
  return app;
}
