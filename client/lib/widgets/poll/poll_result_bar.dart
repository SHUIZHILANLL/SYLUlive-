import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class PollResultBar extends StatelessWidget {
  final double ratio;
  /// 为 null 时用品牌色（品牌色可被主题包覆盖，所以不能做 const 默认值）。
  final Color? color;

  const PollResultBar({
    super.key,
    required this.ratio,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final value = ratio.clamp(0.0, 1.0);
    final barColor = color ?? AppColors.brandPrimary;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 5,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: barColor.withValues(alpha: 0.12)),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: ColoredBox(color: barColor.withValues(alpha: 0.72)),
            ),
          ],
        ),
      ),
    );
  }
}
