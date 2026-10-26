import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// 从自定义背景图里提取一个"能当品牌色"的种子色。
///
/// 目标不是"平均色"（通常灰扑扑），而是**画面里最醒目的那一类颜色**：
/// 按饱和度×中间亮度加权，再归一化到品牌色可用的明度/饱和度区间。
class BackgroundSeed {
  const BackgroundSeed._();

  /// 采样宽度。64px 足够判断色调，解码开销可忽略。
  static const int _sampleWidth = 64;

  /// 背景来源可能是**本地文件**（用户自己选的图）也可能是**内置资源**
  /// （默认壁纸就是 `morenbeijing.jpeg` 这种 asset key），所以这里两条都试。
  static Future<Color?> fromSource(String source) async {
    if (source.isEmpty) return null;
    final file = File(source);
    if (file.existsSync()) return fromFile(source);
    for (final key in <String>[source, 'assets/$source', 'assets/images/$source']) {
      try {
        final data = await rootBundle.load(key);
        return fromBytes(data.buffer.asUint8List());
      } catch (_) {
        // 换下一个候选 key
      }
    }
    return null;
  }

  static Future<Color?> fromFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return fromBytes(bytes);
    } catch (_) {
      return null;
    }
  }

  static Future<Color?> fromBytes(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _sampleWidth,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      frame.image.dispose();
      if (data == null) return null;
      return _pick(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static Color? _pick(Uint8List rgba) {
    double wSum = 0;
    double rSum = 0;
    double gSum = 0;
    double bSum = 0;

    // 保底：所有不透明像素的均值
    double allR = 0;
    double allG = 0;
    double allB = 0;
    int allCount = 0;

    for (var i = 0; i + 3 < rgba.length; i += 4) {
      final a = rgba[i + 3];
      if (a < 200) continue;
      final r = rgba[i].toDouble();
      final g = rgba[i + 1].toDouble();
      final b = rgba[i + 2].toDouble();
      allR += r;
      allG += g;
      allB += b;
      allCount++;

      final hsl = HSLColor.fromColor(Color.fromARGB(255, r.toInt(), g.toInt(), b.toInt()));
      // 太灰的（阴影/白墙）和极暗极亮的都不参与
      if (hsl.saturation < 0.20) continue;
      if (hsl.lightness < 0.15 || hsl.lightness > 0.88) continue;
      final weight = hsl.saturation * (1 - (hsl.lightness - 0.55).abs());
      wSum += weight;
      rSum += r * weight;
      gSum += g * weight;
      bSum += b * weight;
    }

    Color base;
    if (wSum > 0.5) {
      base = Color.fromARGB(
        255,
        (rSum / wSum).round().clamp(0, 255),
        (gSum / wSum).round().clamp(0, 255),
        (bSum / wSum).round().clamp(0, 255),
      );
    } else if (allCount > 0) {
      base = Color.fromARGB(
        255,
        (allR / allCount).round().clamp(0, 255),
        (allG / allCount).round().clamp(0, 255),
        (allB / allCount).round().clamp(0, 255),
      );
    } else {
      return null;
    }

    // 归一化：品牌色要够饱和；明度上限压到 0.48，
    // 保证「品牌色底 + 白字」的对比度 ≥3:1（深色模式由 AppTheme 提亮另算）。
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation(hsl.saturation.clamp(0.40, 0.72))
        .withLightness(hsl.lightness.clamp(0.38, 0.48))
        .toColor();
  }
}
