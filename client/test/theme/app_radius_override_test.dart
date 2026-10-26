import 'package:flutter_test/flutter_test.dart';
import 'package:shenliyuan/theme/app_radius.dart';
import 'package:shenliyuan/theme/app_theme.dart';

/// 圆角 token 的运行时覆盖契约。
///
/// 关键不变量：**未应用主题包时，取值必须与历史常量逐一相等**（零视觉回归）；
/// 覆盖值必须夹紧在 0.5×–2×，`pill` 永不可变。
void main() {
  tearDown(AppRadius.resetOverrides);

  group('default values', () {
    test('未覆盖时等于历史常量', () {
      expect(AppRadius.sm, 8.0);
      expect(AppRadius.md, 12.0);
      expect(AppRadius.lg, 16.0);
      expect(AppRadius.sheet, 24.0);
      expect(AppRadius.pill, 999.0);
      expect(AppRadius.isOverridden, isFalse);
    });

    test('AppTheme 兼容常量跟随 token', () {
      expect(AppTheme.borderRadius, AppRadius.md);
      expect(AppTheme.borderRadiusSmall, AppRadius.sm);
      expect(AppTheme.borderRadiusLarge, AppRadius.lg);
    });
  });

  group('overrides', () {
    test('包内合法值原样生效', () {
      AppRadius.applyOverrides(sm: 6, md: 14, lg: 18, sheet: 26);
      expect(AppRadius.sm, 6.0);
      expect(AppRadius.md, 14.0);
      expect(AppRadius.lg, 18.0);
      expect(AppRadius.sheet, 26.0);
      expect(AppRadius.isOverridden, isTrue);
      expect(AppTheme.borderRadius, 14.0);
    });

    test('超出 2× 上界被夹紧', () {
      AppRadius.applyOverrides(md: 100);
      expect(AppRadius.md, AppRadius.defaultMd * AppRadius.maxFactor);
    });

    test('低于 0.5× 下界被夹紧', () {
      AppRadius.applyOverrides(md: 1);
      expect(AppRadius.md, AppRadius.defaultMd * AppRadius.minFactor);
    });

    test('没给的档位保持原值', () {
      AppRadius.applyOverrides(md: 14);
      expect(AppRadius.md, 14.0);
      expect(AppRadius.sm, AppRadius.defaultSm);
      expect(AppRadius.sheet, AppRadius.defaultSheet);
    });

    test('非法值（NaN / 无穷）被忽略', () {
      AppRadius.applyOverrides(md: double.nan, lg: double.infinity);
      expect(AppRadius.md, AppRadius.defaultMd);
      expect(AppRadius.lg, AppRadius.defaultLg);
      expect(AppRadius.isOverridden, isFalse);
    });

    test('pill 不受覆盖影响', () {
      AppRadius.applyOverrides(sm: 20, md: 20, lg: 20, sheet: 20);
      expect(AppRadius.pill, 999.0);
    });

    test('reset 回到出厂值', () {
      AppRadius.applyOverrides(sm: 20, md: 20, lg: 20, sheet: 20);
      AppRadius.resetOverrides();
      expect(AppRadius.isOverridden, isFalse);
      expect(AppRadius.sm, AppRadius.defaultSm);
      expect(AppRadius.md, AppRadius.defaultMd);
      expect(AppRadius.lg, AppRadius.defaultLg);
      expect(AppRadius.sheet, AppRadius.defaultSheet);
    });
  });
}
