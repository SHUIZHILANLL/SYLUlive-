import 'dart:io';

import 'package:flutter/material.dart';

/// 主题包角色插画的运行时持有者。
class ThemePackMascot {
  ThemePackMascot._();

  static String? _idlePath;

  /// 路径的可监听版本。
  ///
  /// 为什么需要它：承载方（空态插画）在父级重建时可能被判定为相等而跳过
  /// 子树重建，于是读到的还是旧路径；改成监听 notifier 才能即时换图。
  static final ValueNotifier<String?> pathNotifier =
      ValueNotifier<String?>(null);

  /// 状态插图（加载/空态/错误态）路径。
  static final ValueNotifier<String?> stateArtNotifier =
      ValueNotifier<String?>(null);

  static String? get stateArtPath => stateArtNotifier.value;

  static void setStateArt(String? path) => stateArtNotifier.value = path;

  static String? get idlePath => _idlePath;

  /// 是否启用「App 内角色水印」（由包的 mascotBadge 能力决定）。

  static void setPath(String? path) {
    _idlePath = path;
    pathNotifier.value = path;
  }

  static void clear() {
    _idlePath = null;
    pathNotifier.value = null;
  }

  /// 路径存在且文件真的在。
  static bool get available {
    final path = _idlePath;
    if (path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }
}

/// 空态/错误态用的固定尺寸角色图。
class PackMascotImage extends StatelessWidget {
  const PackMascotImage({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    final path = ThemePackMascot.idlePath;
    if (path == null || !File(path).existsSync()) {
      return const SizedBox.shrink();
    }
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
  }
}

/// App 内角色水印：可拖动，松手吸附到最近的左右边缘。
///
/// 手感"跟手"的四个关键：
/// 1. `Listener` 收原始指针事件 —— 不等手势竞技场（否则要先输给列表滚动）；
/// 2. 用 `event.position` 的**绝对坐标**定位 —— 不累加 delta，
///    掉帧/丢事件都不会累积误差，天然 1:1 跟手；
/// 3. 按下瞬间就让小人跳到手指处（`onPointerDown` 也算一次定位），
///    不用"先精确抓到图标才能拖"；
/// 4. 位置存 `ValueNotifier`，不调 setState；图片是常量 child 只构建一次。
/// 主题包提供的状态插图（加载 / 空态 / 错误态）。
///
/// 没有该资产时返回 null，由调用方回落到原来的圆形图标。
class PackStateArt extends StatelessWidget {
  const PackStateArt({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: ThemePackMascot.stateArtNotifier,
      builder: (context, path, _) {
        if (path == null || !File(path).existsSync()) {
          return const SizedBox.shrink();
        }
        return Image.file(
          File(path),
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stack) => const SizedBox.shrink(),
        );
      },
    );
  }
}
